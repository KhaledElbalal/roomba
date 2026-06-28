class AgentHarness
  # Appends `agent_artifacts` rows in monotonic `sequence` order and keeps the
  # running cost/token totals the orchestrator caches onto the run. One row per
  # loop step (thinking/read_file/edit_file/run_command) and one `llm_call` per
  # model call, so the run is fully replayable.
  class ArtifactRecorder
    attr_reader :total_cost_usd, :total_tokens

    def initialize(run)
      @run = run
      # Resume-safe: continue after any artifacts a prior attempt already wrote.
      @sequence = (run.artifacts.maximum(:sequence) || 0)
      @total_cost_usd = BigDecimal(0)
      @total_tokens   = 0
    end

    def record(artifact_type, payload)
      @sequence += 1
      @run.artifacts.create!(
        artifact_type: artifact_type,
        sequence:      @sequence,
        payload:       payload
      )
    end

    def record_llm_call(provider:, model:, input_tokens:, output_tokens:, cost_usd:, fallback:)
      @total_cost_usd += cost_usd
      @total_tokens   += input_tokens + output_tokens

      record(:llm_call, {
        provider:      provider,
        model:         model,
        input_tokens:  input_tokens,
        output_tokens: output_tokens,
        cost_usd:      cost_usd.to_s("F"),
        fallback:      fallback
      })
    end
  end
end
