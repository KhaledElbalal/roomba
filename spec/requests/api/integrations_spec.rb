require "rails_helper"

RSpec.describe "API integrations endpoints", type: :request do
  let(:user_id) { SecureRandom.uuid }

  before do
    stub_jwks
    # Keep specs hermetic: never reach AWS or a provider.
    allow_any_instance_of(Secrets).to receive(:put).and_return("arn:aws:secret:test")
    allow_any_instance_of(Secrets).to receive(:delete)
  end

  describe "GET /api/integrations" do
    it "returns 401 without a token" do
      get "/api/integrations"
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists connected providers without leaking the secret ref" do
      create(:integration, user_id: user_id, provider: :github)
      create(:integration, :linear, user_id: user_id)
      create(:integration, user_id: SecureRandom.uuid, provider: :github) # other user

      get "/api/integrations", headers: auth_headers(user_id)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to contain_exactly(
        { "provider" => "github", "connected" => true },
        { "provider" => "linear", "connected" => true }
      )
      expect(response.body).not_to include("token_secret_ref", "arn:aws")
    end
  end

  describe "POST /api/integrations" do
    it "validates, stores the secret, and upserts the row" do
      allow(ProviderValidation::Github).to receive(:call)
        .with("ghp_token").and_return(login: "octocat")

      expect {
        post "/api/integrations",
          params: { provider: "github", token: "ghp_token" }, headers: auth_headers(user_id)
      }.to change { Integration.for_user(user_id).count }.by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)).to eq("provider" => "github", "connected" => true)

      integration = Integration.for_user(user_id).find_by(provider: :github)
      expect(integration.token_secret_ref).to eq("arn:aws:secret:test")
      expect(integration.metadata).to eq("login" => "octocat")
    end

    it "re-connecting the same provider rotates rather than duplicates" do
      allow(ProviderValidation::Github).to receive(:call).and_return({})
      create(:integration, user_id: user_id, provider: :github, token_secret_ref: "arn:old")

      expect {
        post "/api/integrations",
          params: { provider: "github", token: "ghp_new" }, headers: auth_headers(user_id)
      }.not_to change { Integration.for_user(user_id).count }

      expect(Integration.for_user(user_id).find_by(provider: :github).token_secret_ref)
        .to eq("arn:aws:secret:test")
    end

    it "returns 422 with the provider error when validation fails" do
      allow(ProviderValidation::Github).to receive(:call)
        .and_raise(ProviderValidation::Error, "GitHub rejected the token (HTTP 401)")

      post "/api/integrations",
        params: { provider: "github", token: "ghp_bad" }, headers: auth_headers(user_id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to eq("error" => "GitHub rejected the token (HTTP 401)")
      expect(Integration.for_user(user_id)).to be_empty
    end

    it "returns 422 for an unknown provider" do
      post "/api/integrations",
        params: { provider: "gitlab", token: "x" }, headers: auth_headers(user_id)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 400 when a param is missing" do
      post "/api/integrations", params: { provider: "github" }, headers: auth_headers(user_id)
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "DELETE /api/integrations/:provider" do
    it "removes the row and the underlying secret" do
      create(:integration, user_id: user_id, provider: :github, token_secret_ref: "arn:gh")
      expect_any_instance_of(Secrets).to receive(:delete).with("arn:gh")

      delete "/api/integrations/github", headers: auth_headers(user_id)

      expect(response).to have_http_status(:no_content)
      expect(Integration.for_user(user_id).find_by(provider: :github)).to be_nil
    end

    it "returns 404 for a provider the user has not connected" do
      delete "/api/integrations/github", headers: auth_headers(user_id)
      expect(response).to have_http_status(:not_found)
    end

    it "cannot delete another user's integration" do
      create(:integration, user_id: SecureRandom.uuid, provider: :github)

      delete "/api/integrations/github", headers: auth_headers(user_id)
      expect(response).to have_http_status(:not_found)
    end
  end
end
