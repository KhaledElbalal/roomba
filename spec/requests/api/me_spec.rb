require "spec_helper"

# Hermetic boot: load the Rails environment and rspec/rails support WITHOUT
# touching the database. We deliberately avoid `rails_helper` because it runs
# `ActiveRecord::Migration.maintain_test_schema!`, which requires a live DB.
# These specs never hit the DB (the profile lookup is stubbed).
ENV["RAILS_ENV"] ||= "test"
ENV["NEON_AUTH_JWKS_URL"] ||= "https://neon-auth.example.test/.well-known/jwks.json"
ENV["NEON_AUTH_ISSUER"] ||= "https://neon-auth.example.test"
ENV["NEON_AUTH_AUDIENCE"] ||= "roomba"

require_relative "../../../config/environment"
require "rspec/rails"
require "jwt"
require "openssl"

RSpec.describe "GET /api/me", type: :request do
  # An RSA keypair generated in-process; the public JWK is served to the
  # verifier via a stubbed JWKS fetch so the round-trip is fully offline.
  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:kid) { "test-key-1" }
  let(:jwk) { JWT::JWK.new(rsa_key, kid: kid) }
  let(:jwks_hash) { { keys: [ jwk.export.merge(alg: "RS256", use: "sig") ] } }
  let(:sub) { "user_abc123" }

  before do
    # Reset and stub the in-memory JWKS cache by intercepting the network fetch.
    Authentication.jwks_cache = nil
    allow_any_instance_of(Authentication)
      .to receive(:fetch_jwks).and_return(jwks_hash.deep_stringify_keys)
    # Keep specs hermetic: never touch the DB for the profile lookup. We stub the
    # controller's private `profile` helper so the NeonAuthUser model (and thus
    # the DB) is never reached.
    allow_any_instance_of(Api::MeController).to receive(:profile).and_return(nil)
  end

  def token_for(payload, key: rsa_key, header: { kid: kid })
    JWT.encode(payload, key, "RS256", header)
  end

  def valid_payload(overrides = {})
    {
      "sub" => sub,
      "iss" => ENV["NEON_AUTH_ISSUER"],
      "aud" => ENV["NEON_AUTH_AUDIENCE"],
      "exp" => (Time.now + 300).to_i,
      "iat" => Time.now.to_i
    }.merge(overrides)
  end

  it "returns 401 when no token is supplied" do
    get "/api/me"

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)).to eq("error" => "unauthorized")
  end

  it "returns 401 for a garbage token" do
    get "/api/me", headers: { "Authorization" => "Bearer not-a-real-jwt" }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)).to eq("error" => "unauthorized")
  end

  it "returns 401 for a token signed by an unknown key" do
    other_key = OpenSSL::PKey::RSA.generate(2048)
    token = token_for(valid_payload, key: other_key)

    get "/api/me", headers: { "Authorization" => "Bearer #{token}" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 401 for an expired token" do
    token = token_for(valid_payload("exp" => (Time.now - 60).to_i))

    get "/api/me", headers: { "Authorization" => "Bearer #{token}" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 401 when the issuer does not match" do
    token = token_for(valid_payload("iss" => "https://evil.example"))

    get "/api/me", headers: { "Authorization" => "Bearer #{token}" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 200 with the user_id from `sub` for a valid token" do
    token = token_for(valid_payload)

    get "/api/me", headers: { "Authorization" => "Bearer #{token}" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["user_id"]).to eq(sub)
    expect(body).to have_key("profile")
    expect(body["profile"]).to be_nil
  end
end
