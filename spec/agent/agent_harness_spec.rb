require "rails_helper"

RSpec.describe AgentHarness do
  let(:provider) do
    create(:llm_provider, provider_name: "openai", base_url: "https://api.openai.com/v1",
           available_models: [ "gpt-4o" ])
  end
  let(:run) do
    create(:run, llm_provider: provider, github_repo: "acme/api",
           name: "Add a thing", description: "Please add a thing.",
           max_iterations: 10)
  end

  let(:secrets) { instance_double(AgentHarness::SecretResolver) }
  let(:runner)  { instance_double(AgentHarness::CommandRunner) }

  def ok(stdout = "")
    AgentHarness::CommandRunner::Result.new(stdout: stdout, stderr: "", exit_status: 0)
  end

  def completion(tool_calls:, content: nil)
    AgentHarness::LlmClient::Completion.new(
      content: content, tool_calls: tool_calls,
      input_tokens: 120, output_tokens: 60, model: "gpt-4o"
    )
  end

  def tool(name, args)
    { "id" => SecureRandom.hex(3), "function" => { "name" => name, "arguments" => args.to_json } }
  end

  before do
    @workspace_root = Dir.mktmpdir("roomba-spec")
    ENV["AGENT_WORKSPACE"] = @workspace_root

    create(:integration, user_id: run.user_id, provider: :github,
           token_secret_ref: "ref:gh")

    allow(secrets).to receive(:resolve).and_return("ghp_secret")
    # git status reports a change so the run has something to PR; all other git
    # commands succeed.
    allow(runner).to receive(:run!).and_return(ok("M app/thing.rb"))
    allow(runner).to receive(:run).and_return(ok)
  end

  after do
    ENV.delete("AGENT_WORKSPACE")
    FileUtils.remove_entry(@workspace_root) if @workspace_root && Dir.exist?(@workspace_root)
  end

  subject(:harness) { described_class.new(run_id: run.id, secrets: secrets, runner: runner) }

  context "happy path: edits, green tests, PR opened" do
    let(:pull_request) do
      AgentHarness::GithubClient::PullRequest.new(html_url: "https://github.com/acme/api/pull/7", number: 7)
    end

    before do
      allow_any_instance_of(AgentHarness::LlmClient).to receive(:chat).and_return(
        completion(tool_calls: [
          tool("edit_file", { path: "app/thing.rb", content: "puts :hi" }),
          tool("finish", { summary: "added the thing" })
        ])
      )
      github = instance_double(AgentHarness::GithubClient, open_pull_request: pull_request)
      allow(AgentHarness::GithubClient).to receive(:new).and_return(github)
    end

    it "finishes succeeded with PR fields, cached cost/tokens, and finished_at set" do
      harness.call
      run.reload

      expect(run.status).to eq("succeeded")
      expect(run.github_pr_url).to eq("https://github.com/acme/api/pull/7")
      expect(run.pr_opened_at).to be_present
      expect(run.finished_at).to be_present
      expect(run.started_at).to be_present
      expect(run.tokens_used).to eq(180)
      expect(run.cost_usd).to be > 0
    end

    it "emits llm_call and edit_file artifacts in sequence" do
      harness.call
      types = run.artifacts.order(:sequence).pluck(:artifact_type)
      expect(types).to include("llm_call", "edit_file")
      expect(types.first).to eq("llm_call")
    end

    it "resolves secrets via the resolver and never persists raw secrets on the run" do
      harness.call
      expect(secrets).to have_received(:resolve).with("ref:gh")
      expect(run.reload.attributes.values).not_to include("ghp_secret")
    end
  end

  context "loop hits a bound before finishing" do
    before do
      run.update!(max_iterations: 1)
      # Never calls finish, so the bound is what stops the loop.
      allow_any_instance_of(AgentHarness::LlmClient).to receive(:chat).and_return(
        completion(tool_calls: [ tool("edit_file", { path: "a.rb", content: "x" }) ])
      )
    end

    it "ends failed with the bound recorded and no PR" do
      expect(AgentHarness::GithubClient).not_to receive(:new)
      harness.call
      run.reload

      expect(run.status).to eq("failed")
      expect(run.failure_reason).to eq("max_iterations")
      expect(run.github_pr_url).to be_nil
      expect(run.finished_at).to be_present
    end
  end

  context "tests fail after a clean completion" do
    before do
      allow_any_instance_of(AgentHarness::LlmClient).to receive(:chat).and_return(
        completion(tool_calls: [ tool("finish", { summary: "done" }) ])
      )
      allow(AgentHarness::TestRunner).to receive(:new).and_return(
        instance_double(AgentHarness::TestRunner, call: AgentHarness::TestRunner::Result.new(passed: false, command: "rspec"))
      )
    end

    it "ends failed with reason 'tests failed' and opens no PR" do
      expect(AgentHarness::GithubClient).not_to receive(:new)
      harness.call

      expect(run.reload.status).to eq("failed")
      expect(run.failure_reason).to eq("tests failed")
    end
  end

  context "an unexpected error aborts the run" do
    before do
      allow(secrets).to receive(:resolve).and_raise(AgentHarness::SecretResolver::SecretNotFound, "boom")
    end

    it "marks the run failed, records the reason, and re-raises" do
      expect { harness.call }.to raise_error(AgentHarness::SecretResolver::SecretNotFound)
      run.reload
      expect(run.status).to eq("failed")
      expect(run.failure_reason).to match(/SecretNotFound/)
      expect(run.finished_at).to be_present
    end
  end
end
