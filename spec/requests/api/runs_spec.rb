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
      expect(body["data"].size).to eq(5)
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

  describe "POST /api/runs" do
    let(:issue) do
      { id: "lin-uuid-1", code: "ROO-5", title: "Add auth",
        description: "wire up Neon Auth", type: "feature" }
    end
    let(:payload) do
      { github_repo: "acme/api", dockerfile_path: "Dockerfile.agent",
        llm_provider_id: provider.id, linear_issue: issue }
    end

    # Capture whether the run row was already committed at the moment enqueue
    # ran, so we can prove row-before-enqueue rather than just that both happened.
    let(:queue) { instance_double(DbRunQueue) }
    let(:persisted_at_enqueue) { [] }

    before do
      allow(RunQueue).to receive(:build).and_return(queue)
      allow(queue).to receive(:enqueue) { |run| persisted_at_enqueue << Run.exists?(run.id) }
    end

    def post_run(body = payload, as_user: user_id)
      post "/api/runs", params: body, headers: auth_headers(as_user), as: :json
    end

    it "returns 401 without a token" do
      post "/api/runs", params: payload, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a queued run and returns 202 with id + status" do
      expect { post_run }.to change(Run, :count).by(1)

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body).to eq("id" => Run.last.id, "status" => "queued")
    end

    it "enqueues the run only after the row is committed" do
      post_run

      expect(queue).to have_received(:enqueue).with(Run.last)
      expect(persisted_at_enqueue).to eq([ true ])
    end

    # The inverse of row-before-enqueue: if the transaction rolls back, no
    # message may go out — otherwise the queue would reference a row that never
    # committed (a phantom message).
    it "does not enqueue when the run fails to persist inside the transaction" do
      allow(Run).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Run.new))

      expect { post_run }.not_to change(Run, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(queue).not_to have_received(:enqueue)
    end

    it "caches the Linear issue into linear_tasks and links it" do
      expect { post_run }.to change(LinearTask, :count).by(1)

      task = LinearTask.find_by(code: "ROO-5")
      expect(task).to have_attributes(name: "Add auth", description: "wire up Neon Auth", task_type: "feature")
      expect(task.synced_at).to be_present
      expect(Run.last.linear_task_id).to eq(task.id)
      expect(Run.last.linear_id).to eq("lin-uuid-1")
    end

    it "derives bugfix task_type from the issue type" do
      post_run(payload.merge(linear_issue: issue.merge(type: "bugfix")))
      expect(LinearTask.find_by(code: "ROO-5").task_type).to eq("bugfix")
    end

    it "refreshes an existing cached task rather than duplicating it" do
      create(:linear_task, code: "ROO-5", name: "stale name")

      expect { post_run }.not_to change(LinearTask, :count)
      expect(LinearTask.find_by(code: "ROO-5").name).to eq("Add auth")
    end

    it "defaults bounds sensibly when omitted" do
      post_run

      run = Run.last
      expect(run.max_iterations).to eq(20)
      expect(run.max_wall_clock_seconds).to eq(1800)
      expect(run.max_cost_usd).to eq(5.0)
    end

    it "respects bounds when provided" do
      post_run(payload.merge(max_iterations: 3, max_wall_clock_seconds: 120, max_cost_usd: 1.25))

      run = Run.last
      expect(run.max_iterations).to eq(3)
      expect(run.max_wall_clock_seconds).to eq(120)
      expect(run.max_cost_usd).to eq(1.25)
    end

    it "persists the optional fallback provider and env ref" do
      fallback = create(:llm_provider, user_id: user_id)
      post_run(payload.merge(llm_provider_fallback_id: fallback.id, env_secret_ref: "arn:aws:env"))

      run = Run.last
      expect(run.llm_provider_fallback_id).to eq(fallback.id)
      expect(run.env_secret_ref).to eq("arn:aws:env")
    end

    context "idempotency (FR-4)" do
      it "rejects a second trigger while a run for the task is active" do
        task = create(:linear_task, code: "ROO-5")
        existing = create(:run, :running, user_id: user_id, llm_provider: provider, linear_task: task)

        expect { post_run }.not_to change(Run, :count)

        expect(response).to have_http_status(:conflict)
        body = JSON.parse(response.body)
        expect(body["run"]).to eq("id" => existing.id, "status" => "running")
        expect(queue).not_to have_received(:enqueue)
      end

      it "allows a new run once the prior one is in a terminal state" do
        task = create(:linear_task, code: "ROO-5")
        create(:run, :succeeded, user_id: user_id, llm_provider: provider, linear_task: task)

        expect { post_run }.to change(Run, :count).by(1)
        expect(response).to have_http_status(:accepted)
      end

      it "is user-scoped: another user's active run does not block this user" do
        task = create(:linear_task, code: "ROO-5")
        other = create(:llm_provider, user_id: other_user_id)
        create(:run, :running, user_id: other_user_id, llm_provider: other, linear_task: task)

        expect { post_run }.to change(Run, :count).by(1)
        expect(response).to have_http_status(:accepted)
      end
    end

    context "provider ownership" do
      it "rejects a provider belonging to another user" do
        other = create(:llm_provider, user_id: other_user_id)

        expect { post_run(payload.merge(llm_provider_id: other.id)) }.not_to change(Run, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects a non-existent provider" do
        post_run(payload.merge(llm_provider_id: 0))
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects a fallback provider belonging to another user" do
        other = create(:llm_provider, user_id: other_user_id)

        post_run(payload.merge(llm_provider_fallback_id: other.id))
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "missing required params" do
      it "requires github_repo" do
        post_run(payload.except(:github_repo))
        expect(response).to have_http_status(:bad_request)
      end

      it "requires llm_provider_id" do
        post_run(payload.except(:llm_provider_id))
        expect(response).to have_http_status(:bad_request)
      end

      it "requires the linear_issue" do
        post_run(payload.except(:linear_issue))
        expect(response).to have_http_status(:bad_request)
      end

      it "requires the issue code and title" do
        post_run(payload.merge(linear_issue: { title: "no code" }))
        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end
