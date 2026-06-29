require "rails_helper"

RSpec.describe "API Linear proxy", type: :request do
  let(:user_id) { SecureRandom.uuid }

  before { stub_jwks }

  describe "GET /api/linear/issues" do
    it "returns 401 without a token" do
      get "/api/linear/issues"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 409 with a connect prompt when Linear isn't connected" do
      get "/api/linear/issues", headers: auth_headers(user_id)

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)).to eq("error" => "linear is not connected")
    end

    it "resolves the token from Secrets and returns the minimal issue shape" do
      create(:integration, :linear, user_id: user_id, token_secret_ref: "arn:lin")
      allow_any_instance_of(Secrets).to receive(:get).with("arn:lin").and_return("lin_token")
      allow(ProviderProxy::LinearIssues).to receive(:call).with("lin_token").and_return([
        { id: "uuid-1", code: "ROO-5", title: "Auth", description: "do it", type: "feature" }
      ])

      get "/api/linear/issues", headers: auth_headers(user_id)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([
        { "id" => "uuid-1", "code" => "ROO-5", "title" => "Auth",
          "description" => "do it", "type" => "feature" }
      ])
    end

    it "maps a revoked token to 502, not 500" do
      create(:integration, :linear, user_id: user_id, token_secret_ref: "arn:lin")
      allow_any_instance_of(Secrets).to receive(:get).and_return("lin_revoked")
      allow(ProviderProxy::LinearIssues).to receive(:call)
        .and_raise(ProviderProxy::Error.new("Linear rejected the token (HTTP 200)", status: :bad_gateway))

      get "/api/linear/issues", headers: auth_headers(user_id)

      expect(response).to have_http_status(:bad_gateway)
      expect(JSON.parse(response.body)).to eq("error" => "Linear rejected the token (HTTP 200)")
    end

    it "maps a rate limit to 429" do
      create(:integration, :linear, user_id: user_id, token_secret_ref: "arn:lin")
      allow_any_instance_of(Secrets).to receive(:get).and_return("lin_token")
      allow(ProviderProxy::LinearIssues).to receive(:call)
        .and_raise(ProviderProxy::Error.new("Linear rate limit exceeded", status: :too_many_requests))

      get "/api/linear/issues", headers: auth_headers(user_id)

      expect(response).to have_http_status(:too_many_requests)
    end

    it "is user-scoped: another user's Linear connection does not satisfy the request" do
      create(:integration, :linear, user_id: SecureRandom.uuid)

      get "/api/linear/issues", headers: auth_headers(user_id)

      expect(response).to have_http_status(:conflict)
    end
  end
end
