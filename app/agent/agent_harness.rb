require "open3"
require "net/http"
require "tmpdir"
require "fileutils"
require "base64"
require "bigdecimal"

# Entry point for the containerized agent. Dockerfile.agent runs
# `rails runner AgentHarness.run`; the runner (ROO-13) launches the task with
# AGENT_RUN_ID set. One invocation drives a single run end to end: resolve
# secrets, clone the target repo, run the bounded LLM edit loop, run the repo's
# tests, open a PR on green, and leave the run in a terminal state with
# cost/tokens cached. Loop *quality* is deliberately out of scope (follow-ups).
class AgentHarness
  DEFAULT_WORKSPACE = "/workspace".freeze

  def self.run(run_id: ENV["AGENT_RUN_ID"])
    new(run_id: run_id).call
  end

  def initialize(run_id:, secrets: SecretResolver.new, runner: CommandRunner.new, logger: Rails.logger)
    raise ArgumentError, "AGENT_RUN_ID is required" if run_id.blank?

    @run      = Run.find(run_id)
    @secrets  = secrets
    @runner   = runner
    @logger   = logger
    @recorder = ArtifactRecorder.new(@run)
  end

  def call
    start!
    pat       = github_pat
    workspace = clone(pat)
    providers = build_providers

    loop_result = EditLoop.new(
      run: @run, workspace: workspace, providers: providers,
      recorder: @recorder, bounds: Bounds.from(@run)
    ).call

    conclude(workspace, pat, loop_result)
  rescue => e
    # Unexpected failure (clone error, secret miss, bug): record and re-raise so
    # the container exits non-zero and the runner can surface it.
    abort_run!(e)
    raise
  ensure
    finalize!
  end

  private

  def start!
    @run.update!(status: :running, started_at: Time.current)
  end

  def github_pat
    integration = Integration.for_user(@run.user_id).find_by!(provider: :github)
    @secrets.resolve(integration.token_secret_ref)
  end

  def clone(pat)
    Workspace.clone(
      repo: @run.github_repo, pat: pat, run_id: @run.id,
      dir: File.join(workspace_root, "repo"), runner: @runner
    )
  end

  def build_providers
    ProviderChain.new(
      primary:  provider_member(@run.llm_provider),
      fallback: provider_member(@run.llm_provider_fallback)
    )
  end

  def provider_member(provider)
    return nil unless provider

    client = LlmClient.new(
      base_url: provider.base_url,
      api_key:  @secrets.resolve(provider.api_key_secret_ref),
      model:    Array(provider.available_models).first
    )
    ProviderChain::Member.new(client: client, provider_name: provider.provider_name)
  end

  # Decide the terminal outcome. Success requires a clean completion (no bound
  # breach), passing tests, and an actual change to propose. Anything else is a
  # failure whose reason is recorded.
  def conclude(workspace, pat, loop_result)
    if loop_result.stop_reason != :completed
      return mark_failed(loop_result.stop_reason.to_s)
    end
    return mark_failed("no changes produced") unless workspace.changes?

    tests = TestRunner.new(workspace: workspace, recorder: @recorder).call
    return mark_failed("tests failed") unless tests.passed?

    open_pull_request(workspace, pat)
    @run.status = :succeeded
  end

  def open_pull_request(workspace, pat)
    workspace.commit_all(commit_message)
    workspace.push

    pr = GithubClient.new(pat: pat, repo: @run.github_repo)
      .open_pull_request(head: workspace.branch, title: pr_title, body: pr_body)

    @run.github_pr_url = pr.html_url
    @run.pr_opened_at  = Time.current
  end

  def mark_failed(reason)
    @run.status = :failed
    @run.failure_reason = reason
  end

  def abort_run!(error)
    @run.status = :failed
    @run.failure_reason = "#{error.class}: #{error.message}"
    @logger.error("[AgentHarness] run #{@run.id} aborted: #{error.class}: #{error.message}")
  end

  # Always runs: cache cost/tokens totals and stamp the terminal time, even when
  # the run aborted, so the API reflects what actually happened.
  def finalize!
    # Defensive: every code path above sets a terminal status, but never leave a
    # finished run marked `running`.
    @run.status = :failed unless @run.succeeded? || @run.failed?
    @run.cost_usd    = @recorder.total_cost_usd
    @run.tokens_used = @recorder.total_tokens
    @run.finished_at ||= Time.current
    @run.save!
  end

  def workspace_root
    ENV["AGENT_WORKSPACE"].presence || DEFAULT_WORKSPACE
  end

  def commit_message = "#{pr_title}\n\nOpened by the Roomba agent for run #{@run.id}."
  def pr_title       = (@run.name.presence || "Roomba agent changes for run #{@run.id}")

  def pr_body
    [
      @run.description.presence,
      "—",
      "Automated change by the Roomba agent (run #{@run.id})."
    ].compact.join("\n\n")
  end
end
