require "rails_helper"

RSpec.describe "API GitHub proxy", type: :request do
  let(:user_id) { SecureRandom.uuid }

  before { stub_jwks }

  describe "GET /api/github/repos" do
    it "returns 401 without a token" do
      get "/api/github/repos"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 409 with a connect prompt when GitHub isn't connected" do
      get "/api/github/repos", headers: auth_headers(user_id)

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)).to eq("error" => "github is not connected")
    end

    it "resolves the token from Secrets and returns the minimal repo shape" do
      create(:integration, user_id: user_id, provider: :github, token_secret_ref: "arn:gh")
      allow_any_instance_of(Secrets).to receive(:get).with("arn:gh").and_return("ghp_token")
      allow(ProviderProxy::GithubRepos).to receive(:call).with("ghp_token").and_return([
        { name: "roomba", full_name: "acme/roomba", default_branch: "main", private: true }
      ])

      get "/api/github/repos", headers: auth_headers(user_id)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([
        { "name" => "roomba", "full_name" => "acme/roomba",
          "default_branch" => "main", "private" => true }
      ])
    end

    it "maps a revoked token to 502, not 500" do
      create(:integration, user_id: user_id, provider: :github, token_secret_ref: "arn:gh")
      allow_any_instance_of(Secrets).to receive(:get).and_return("ghp_revoked")
      allow(ProviderProxy::GithubRepos).to receive(:call)
        .and_raise(ProviderProxy::Error.new("GitHub rejected the token (HTTP 401)", status: :bad_gateway))

      get "/api/github/repos", headers: auth_headers(user_id)

      expect(response).to have_http_status(:bad_gateway)
      expect(JSON.parse(response.body)).to eq("error" => "GitHub rejected the token (HTTP 401)")
    end

    it "maps a rate limit to 429" do
      create(:integration, user_id: user_id, provider: :github, token_secret_ref: "arn:gh")
      allow_any_instance_of(Secrets).to receive(:get).and_return("ghp_token")
      allow(ProviderProxy::GithubRepos).to receive(:call)
        .and_raise(ProviderProxy::Error.new("GitHub rate limit exceeded", status: :too_many_requests))

      get "/api/github/repos", headers: auth_headers(user_id)

      expect(response).to have_http_status(:too_many_requests)
    end

    it "is user-scoped: another user's GitHub connection does not satisfy the request" do
      create(:integration, user_id: SecureRandom.uuid, provider: :github)

      get "/api/github/repos", headers: auth_headers(user_id)

      expect(response).to have_http_status(:conflict)
    end
  end
end
