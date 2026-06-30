require "rails_helper"

RSpec.describe Runs::CreateCommand do
  let(:user_id)  { SecureRandom.uuid }
  let(:provider) { create(:llm_provider, user_id: user_id) }
  let(:queue)    { instance_double(DbRunQueue, enqueue: nil) }
  let(:issue) do
    { id: "lin-uuid-1", code: "ROO-5", title: "Add auth",
      description: "wire up Neon Auth", type: "feature" }
  end

  def run_command(**overrides)
    described_class.new(
      user_id: user_id, issue: issue, repo: "acme/api",
      provider: provider, queue: queue, **overrides
    ).call
  end

  describe "#call" do
    it "creates a queued run and returns it in the result" do
      result = nil
      expect { result = run_command }.to change(Run, :count).by(1)

      expect(result).not_to be_duplicate
      expect(result.run).to have_attributes(status: "queued", github_repo: "acme/api", user_id: user_id)
    end

    it "enqueues the run only after it is committed" do
      persisted_at_enqueue = nil
      allow(queue).to receive(:enqueue) { |run| persisted_at_enqueue = Run.exists?(run.id) }

      result = run_command

      expect(queue).to have_received(:enqueue).with(result.run)
      expect(persisted_at_enqueue).to be(true)
    end

    it "caches the Linear issue into linear_tasks and links it" do
      expect { run_command }.to change(LinearTask, :count).by(1)

      task = LinearTask.find_by(code: "ROO-5")
      expect(task).to have_attributes(name: "Add auth", description: "wire up Neon Auth", task_type: "feature")
      expect(task.synced_at).to be_present
      expect(Run.last).to have_attributes(linear_task_id: task.id, linear_id: "lin-uuid-1")
    end

    it "refreshes an existing cached task rather than duplicating it" do
      create(:linear_task, code: "ROO-5", name: "stale", description: "old")

      expect { run_command }.not_to change(LinearTask, :count)
      expect(LinearTask.find_by(code: "ROO-5")).to have_attributes(name: "Add auth", description: "wire up Neon Auth")
    end

    it "maps an unknown issue type to feature" do
      run_command(issue: issue.merge(type: "chore"))
      expect(LinearTask.find_by(code: "ROO-5").task_type).to eq("feature")
    end

    it "persists the optional fallback, dockerfile and env ref" do
      fallback = create(:llm_provider, user_id: user_id)

      run_command(fallback: fallback, dockerfile_path: "Dockerfile.agent", env_secret_ref: "arn:aws:env")

      expect(Run.last).to have_attributes(
        llm_provider_fallback_id: fallback.id,
        dockerfile_path:          "Dockerfile.agent",
        env_secret_ref:           "arn:aws:env"
      )
    end

    describe "bounds" do
      it "defaults sensibly when omitted" do
        run_command

        expect(Run.last).to have_attributes(
          max_iterations: 20, max_wall_clock_seconds: 1800, max_cost_usd: 5.0
        )
      end

      it "uses caller-supplied bounds, ignoring blanks" do
        run_command(bounds: { max_iterations: 3, max_wall_clock_seconds: "", max_cost_usd: 1.25 })

        expect(Run.last).to have_attributes(
          max_iterations: 3, max_wall_clock_seconds: 1800, max_cost_usd: 1.25
        )
      end
    end

    describe "idempotency (FR-4)" do
      it "returns the active run as a duplicate and does not enqueue" do
        task     = create(:linear_task, code: "ROO-5")
        existing = create(:run, :running, user_id: user_id, llm_provider: provider, linear_task: task)

        result = nil
        expect { result = run_command }.not_to change(Run, :count)

        expect(result).to be_duplicate
        expect(result.run).to be_nil
        expect(result.duplicate).to eq(existing)
        expect(queue).not_to have_received(:enqueue)
      end

      it "allows a new run once the prior one is terminal" do
        task = create(:linear_task, code: "ROO-5")
        create(:run, :succeeded, user_id: user_id, llm_provider: provider, linear_task: task)

        expect { run_command }.to change(Run, :count).by(1)
      end

      it "is user-scoped: another user's active run does not block this user" do
        task  = create(:linear_task, code: "ROO-5")
        other = create(:llm_provider, user_id: SecureRandom.uuid)
        create(:run, :running, user_id: other.user_id, llm_provider: other, linear_task: task)

        result = nil
        expect { result = run_command }.to change(Run, :count).by(1)
        expect(result).not_to be_duplicate
      end
    end

    it "does not enqueue when the run fails to persist" do
      allow(Run).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Run.new))

      expect { run_command }.to raise_error(ActiveRecord::RecordInvalid)
      expect(queue).not_to have_received(:enqueue)
      expect(Run.count).to eq(0)
    end
  end
end
