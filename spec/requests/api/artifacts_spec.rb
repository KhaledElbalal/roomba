require "rails_helper"

RSpec.describe "API artifacts endpoints", type: :request do
  let(:user_id)       { SecureRandom.uuid }
  let(:other_user_id) { SecureRandom.uuid }
  let!(:provider)     { create(:llm_provider, user_id: user_id) }
  let!(:run)          { create(:run, user_id: user_id, llm_provider: provider) }

  before { stub_jwks }

  describe "GET /api/runs/:run_id/artifacts" do
    it "returns 401 without a token" do
      get "/api/runs/#{run.id}/artifacts"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 404 when the run belongs to another user" do
      other_run = create(:run, user_id: other_user_id, llm_provider: create(:llm_provider, user_id: other_user_id))

      get "/api/runs/#{other_run.id}/artifacts", headers: auth_headers(user_id)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-existent run" do
      get "/api/runs/0/artifacts", headers: auth_headers(user_id)
      expect(response).to have_http_status(:not_found)
    end

    it "returns all artifacts for the run in sequence order" do
      a2 = create(:artifact, run: run, sequence: 2, artifact_type: :llm_call)
      a1 = create(:artifact, run: run, sequence: 1, artifact_type: :thinking)
      a3 = create(:artifact, run: run, sequence: 3, artifact_type: :edit_file)

      get "/api/runs/#{run.id}/artifacts", headers: auth_headers(user_id)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"].map { |a| a["id"] }).to eq([ a1.id, a2.id, a3.id ])
    end

    it "returns pagination metadata" do
      create_list(:artifact, 3, run: run, artifact_type: :llm_call)

      get "/api/runs/#{run.id}/artifacts", headers: auth_headers(user_id)

      body = JSON.parse(response.body)
      expect(body).to include("page" => 1, "per_page" => 50, "total" => 3)
    end

    it "filters by artifact_type" do
      create(:artifact, run: run, sequence: 1, artifact_type: :thinking)
      create(:artifact, run: run, sequence: 2, artifact_type: :llm_call)
      create(:artifact, run: run, sequence: 3, artifact_type: :llm_call)

      get "/api/runs/#{run.id}/artifacts", params: { type: "llm_call" }, headers: auth_headers(user_id)

      body = JSON.parse(response.body)
      expect(body["total"]).to eq(2)
      expect(body["data"].map { |a| a["artifact_type"] }.uniq).to eq([ "llm_call" ])
    end

    it "returns an empty list when the type filter matches nothing" do
      create(:artifact, run: run, sequence: 1, artifact_type: :thinking)

      get "/api/runs/#{run.id}/artifacts", params: { type: "run_command" }, headers: auth_headers(user_id)

      body = JSON.parse(response.body)
      expect(body["data"]).to be_empty
      expect(body["total"]).to eq(0)
    end

    it "exposes the correct artifact fields" do
      create(:artifact, run: run, sequence: 1, artifact_type: :llm_call,
             payload: { model: "gpt-4o", input_tokens: 100, output_tokens: 50 })

      get "/api/runs/#{run.id}/artifacts", headers: auth_headers(user_id)

      artifact = JSON.parse(response.body)["data"].first
      expect(artifact.keys).to contain_exactly("id", "artifact_type", "sequence", "payload", "created_at")
      expect(artifact["artifact_type"]).to eq("llm_call")
      expect(artifact["sequence"]).to eq(1)
      expect(artifact["payload"]).to include("model" => "gpt-4o")
    end

    it "paginates when there are more artifacts than per_page" do
      create_list(:artifact, 55, run: run, artifact_type: :llm_call)

      get "/api/runs/#{run.id}/artifacts", params: { page: 2 }, headers: auth_headers(user_id)

      body = JSON.parse(response.body)
      expect(body["page"]).to eq(2)
      expect(body["data"].size).to eq(5)   # 55 total, 50 per page → page 2 has 5
      expect(body["total"]).to eq(55)
    end

    it "does not leak artifacts from another user's run" do
      other_run = create(:run, user_id: other_user_id, llm_provider: create(:llm_provider, user_id: other_user_id))
      create(:artifact, run: other_run, sequence: 1)

      get "/api/runs/#{other_run.id}/artifacts", headers: auth_headers(user_id)

      expect(response).to have_http_status(:not_found)
    end
  end
end
