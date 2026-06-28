require "rails_helper"

RSpec.describe "API llm_providers endpoints", type: :request do
  let(:user_id) { SecureRandom.uuid }

  before do
    stub_jwks
    allow_any_instance_of(Secrets).to receive(:put).and_return("arn:aws:secret:test")
    allow_any_instance_of(Secrets).to receive(:delete)
    allow(LlmKeyValidator).to receive(:call).and_return(true)
  end

  describe "GET /api/llm_providers" do
    it "returns 401 without a token" do
      get "/api/llm_providers"
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists configured providers without leaking the key ref" do
      create(:llm_provider, user_id: user_id, provider_name: "openai")
      create(:llm_provider, user_id: SecureRandom.uuid) # other user

      get "/api/llm_providers", headers: auth_headers(user_id)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.size).to eq(1)
      expect(body.first.keys).to contain_exactly(
        "id", "provider_name", "base_url", "available_models"
      )
      expect(response.body).not_to include("api_key_secret_ref", "arn:aws")
    end
  end

  describe "POST /api/llm_providers" do
    let(:valid_params) do
      { provider_name: "openai", base_url: "https://api.openai.com/v1",
        available_models: %w[gpt-4o gpt-4o-mini], api_key: "sk-live" }
    end

    it "validates the key, stores the secret, and persists the row" do
      expect(LlmKeyValidator).to receive(:call)
        .with(base_url: "https://api.openai.com/v1", api_key: "sk-live").and_return(true)

      expect {
        post "/api/llm_providers", params: valid_params, headers: auth_headers(user_id)
      }.to change { LlmProvider.for_user(user_id).count }.by(1)

      expect(response).to have_http_status(:created)
      provider = LlmProvider.for_user(user_id).last
      expect(provider.api_key_secret_ref).to eq("arn:aws:secret:test")
      expect(provider.available_models).to eq(%w[gpt-4o gpt-4o-mini])
    end

    it "returns 422 when the key is rejected" do
      allow(LlmKeyValidator).to receive(:call)
        .and_raise(ProviderValidation::Error, "provider rejected the API key (HTTP 401)")

      post "/api/llm_providers", params: valid_params, headers: auth_headers(user_id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(LlmProvider.for_user(user_id)).to be_empty
    end

    it "returns 422 when provider_name is missing" do
      post "/api/llm_providers",
        params: valid_params.except(:provider_name), headers: auth_headers(user_id)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 400 when the api_key is missing" do
      post "/api/llm_providers",
        params: valid_params.except(:api_key), headers: auth_headers(user_id)

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "PATCH /api/llm_providers/:id" do
    it "updates model selection without touching the secret when no key is sent" do
      provider = create(:llm_provider, user_id: user_id, available_models: %w[gpt-4o])
      expect_any_instance_of(Secrets).not_to receive(:put)

      patch "/api/llm_providers/#{provider.id}",
        params: { available_models: %w[gpt-4o gpt-4o-mini] }, headers: auth_headers(user_id)

      expect(response).to have_http_status(:ok)
      expect(provider.reload.available_models).to eq(%w[gpt-4o gpt-4o-mini])
    end

    it "rotates the key in place when a new api_key is supplied" do
      provider = create(:llm_provider, user_id: user_id, api_key_secret_ref: "arn:keep")
      expect(LlmKeyValidator).to receive(:call).and_return(true)
      expect_any_instance_of(Secrets).to receive(:put)
        .with(ref: "arn:keep", value: "sk-rotated").and_return("arn:keep")

      patch "/api/llm_providers/#{provider.id}",
        params: { api_key: "sk-rotated" }, headers: auth_headers(user_id)

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for another user's provider" do
      provider = create(:llm_provider, user_id: SecureRandom.uuid)

      patch "/api/llm_providers/#{provider.id}",
        params: { base_url: "https://x" }, headers: auth_headers(user_id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/llm_providers/:id" do
    it "removes the row and the secret" do
      provider = create(:llm_provider, user_id: user_id, api_key_secret_ref: "arn:key")
      expect_any_instance_of(Secrets).to receive(:delete).with("arn:key")

      delete "/api/llm_providers/#{provider.id}", headers: auth_headers(user_id)

      expect(response).to have_http_status(:no_content)
      expect(LlmProvider.exists?(provider.id)).to be(false)
    end

    it "returns 404 for another user's provider" do
      provider = create(:llm_provider, user_id: SecureRandom.uuid)

      delete "/api/llm_providers/#{provider.id}", headers: auth_headers(user_id)
      expect(response).to have_http_status(:not_found)
    end
  end
end
