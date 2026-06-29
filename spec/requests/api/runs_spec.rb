require "rails_helper"

RSpec.describe "API runs endpoints", type: :request do
  let(:user_id)       { SecureRandom.uuid }
  let(:other_user_id) { SecureRandom.uuid }
  let!(:provider)     { create(:llm_provider, user_id: user_id) }

  before { stub_jwks }

  describe "GET /api/runs" do
    it "returns 401 without a token" do
      get "/api/runs"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns runs for the authenticated user only" do
      create(:run, user_id: user_id,       llm_provider: provider)
      create(:run, user_id: other_user_id, llm_provider: create(:llm_provider, user_id: other_user_id))

      get "/api/runs", headers: auth_headers(user_id)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"].size).to eq(1)
      expect(body["total"]).to eq(1)
    end

    it "returns pagination metadata" do
      create_list(:run, 3, user_id: user_id, llm_provider: provider)

      get "/api/runs", headers: auth_headers(user_id)

      body = JSON.parse(response.body)
      expect(body).to include("page" => 1, "per_page" => 25, "total" => 3)
      expect(body["data"]).to be_an(Array)
    end

    it "returns runs in descending created_at order" do
      oldest = create(:run, user_id: user_id, llm_provider: provider, created_at: 2.hours.ago)
      newest = create(:run, user_id: user_id, llm_provider: provider, created_at: 1.hour.ago)

      get "/api/runs", headers: auth_headers(user_id)

      ids = JSON.parse(response.body)["data"].map { |r| r["id"] }
      expect(ids).to eq([ newest.id, oldest.id ])
    end

    it "filters by status" do
      create(:run, :succeeded, user_id: user_id, llm_provider: provider)
      create(:run, :failed,    user_id: user_id, llm_provider: provider)

      get "/api/runs", params: { status: "succeeded" }, headers: auth_headers(user_id)

      body = JSON.parse(response.body)
      expect(body["data"].size).to eq(1)
      expect(body["data"].first["status"]).to eq("succeeded")
    end

    it "filters by repo" do
      create(:run, user_id: user_id, llm_provider: provider, github_repo: "acme/api")
      create(:run, user_id: user_id, llm_provider: provider, github_repo: "acme/web")

      get "/api/runs", params: { repo: "acme/api" }, headers: auth_headers(user_id)

      body = JSON.parse(response.body)
      expect(body["data"].size).to eq(1)
      expect(body["data"].first["github_repo"]).to eq("acme/api")
    end

    it "does not expose env_secret_ref or user_id" do
      create(:run, user_id: user_id, llm_provider: provider, env_secret_ref: "arn:aws:secretsmanager:secret")

      get "/api/runs", headers: auth_headers(user_id)

      expect(response.body).not_to include("env_secret_ref", "arn:aws", user_id)
    end

    it "exposes expected run fields" do
      create(:run, :succeeded, user_id: user_id, llm_provider: provider, github_repo: "acme/api")

      get "/api/runs", headers: auth_headers(user_id)

      run_json = JSON.parse(response.body)["data"].first
      expect(run_json.keys).to include(
        "id", "status", "github_repo", "github_pr_url",
        "started_at", "finished_at", "deployed_at", "pr_opened_at",
        "cost_usd", "tokens_used", "user_rating", "changes_requested",
        "created_at", "updated_at", "llm_provider", "linear_task"
      )
    end

    it "does not expose api_key_secret_ref on nested llm_provider" do
      create(:run, user_id: user_id, llm_provider: provider)

      get "/api/runs", headers: auth_headers(user_id)

      run_json = JSON.parse(response.body)["data"].first
      expect(run_json["llm_provider"].keys).to contain_exactly("id", "provider_name")
      expect(response.body).not_to include("api_key_secret_ref")
    end

    it "respects page/per_page pagination" do
      create_list(:run, 30, user_id: user_id, llm_provider: provider)

      get "/api/runs", params: { page: 2 }, headers: auth_headers(user_id)

      body = JSON.parse(response.body)
      expect(body["page"]).to eq(2)
      expect(body["data"].size).to eq(5)   # 30 total, 25 per page → page 2 has 5
      expect(body["total"]).to eq(30)
    end
  end

  describe "GET /api/runs/:id" do
    it "returns 401 without a token" do
      run = create(:run, user_id: user_id, llm_provider: provider)
      get "/api/runs/#{run.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 404 for another user's run" do
      other_run = create(:run, user_id: other_user_id, llm_provider: create(:llm_provider, user_id: other_user_id))

      get "/api/runs/#{other_run.id}", headers: auth_headers(user_id)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-existent run" do
      get "/api/runs/0", headers: auth_headers(user_id)
      expect(response).to have_http_status(:not_found)
    end

    it "returns the run with its artifact timeline" do
      run = create(:run, user_id: user_id, llm_provider: provider)
      a1  = create(:artifact, run: run, sequence: 1, artifact_type: :thinking)
      a2  = create(:artifact, run: run, sequence: 2, artifact_type: :llm_call)
      a3  = create(:artifact, run: run, sequence: 3, artifact_type: :edit_file)

      get "/api/runs/#{run.id}", headers: auth_headers(user_id)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(run.id)
      expect(body["artifacts"].map { |a| a["id"] }).to eq([ a1.id, a2.id, a3.id ])
    end

    it "returns artifacts in ascending sequence order" do
      run = create(:run, user_id: user_id, llm_provider: provider)
      create(:artifact, run: run, sequence: 3)
      create(:artifact, run: run, sequence: 1)
      create(:artifact, run: run, sequence: 2)

      get "/api/runs/#{run.id}", headers: auth_headers(user_id)

      sequences = JSON.parse(response.body)["artifacts"].map { |a| a["sequence"] }
      expect(sequences).to eq([ 1, 2, 3 ])
    end

    it "includes linear_task when present" do
      task = create(:linear_task, code: "ROO-42", name: "Fix the thing")
      run  = create(:run, :with_linear_task, user_id: user_id, llm_provider: provider, linear_task: task)

      get "/api/runs/#{run.id}", headers: auth_headers(user_id)

      lt = JSON.parse(response.body)["linear_task"]
      expect(lt).to include("code" => "ROO-42", "name" => "Fix the thing")
      expect(lt.keys).not_to include("user_id")
    end

    it "never exposes env_secret_ref" do
      run = create(:run, user_id: user_id, llm_provider: provider, env_secret_ref: "arn:aws:secret:env")

      get "/api/runs/#{run.id}", headers: auth_headers(user_id)

      expect(response.body).not_to include("env_secret_ref", "arn:aws:secret:env")
    end

    it "exposes artifact fields without leaking secrets" do
      run = create(:run, user_id: user_id, llm_provider: provider)
      create(:artifact, run: run, sequence: 1, artifact_type: :llm_call,
             payload: { model: "gpt-4o", input_tokens: 200, output_tokens: 100 })

      get "/api/runs/#{run.id}", headers: auth_headers(user_id)

      artifact = JSON.parse(response.body)["artifacts"].first
      expect(artifact.keys).to contain_exactly("id", "artifact_type", "sequence", "payload", "created_at")
    end
  end
end
