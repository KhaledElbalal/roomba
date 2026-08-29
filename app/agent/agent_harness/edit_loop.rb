class AgentHarness
  # The plan → read/edit → run → iterate loop. Each turn makes one model call
  # (via ProviderChain, so fallback is automatic), records the `llm_call`, then
  # executes any tool calls. Bounds are checked at the top of every turn and are
  # hard stops: the loop returns the tripped reason so the orchestrator records
  # it. Loop *quality* is intentionally minimal here — this is the scaffolding.
  class EditLoop
    Result = Struct.new(:stop_reason, :iterations, keyword_init: true)

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a software engineering agent working in a cloned git repository at the repository root.
      You have exactly 4 tools: read_file, edit_file, run_command, finish.

      Workflow:
      1. Read relevant files with read_file.
      2. Make the smallest edit that satisfies the task with edit_file.
      3. Optionally verify with run_command (e.g. run tests).
      4. When ALL edits are complete you MUST call finish exactly once with a concise summary — this is the ONLY way to signal completion.

      Rules:
      - Always use a tool call; a prose reply without a tool call does NOT complete the task.
      - Do NOT run git commit, git push, or gh pr create — the harness creates branch roomba/run-{id}, commits, pushes, and opens the pull request automatically after finish if tests pass.
      - Do NOT call finish until all edits are done; do not call it multiple times.
    PROMPT

    def initialize(run:, workspace:, providers:, recorder:, bounds:)
      @run       = run
      @workspace = workspace
      @providers = providers
      @recorder  = recorder
      @bounds    = bounds
    end

    def call
      @bounds.start!
      messages = [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: task_prompt }
      ]

      iteration = 0
      loop do
        if (reason = @bounds.breach(iteration: iteration, cost_usd: @recorder.total_cost_usd))
          return Result.new(stop_reason: reason, iterations: iteration)
        end
        iteration += 1

        call = @providers.chat(messages: messages, tools: Tools::SCHEMA)
        record_call(call)
        messages << assistant_message(call.completion)

        tool_calls = call.completion.tool_calls
        if tool_calls.blank?
          # No tool call means the model answered in prose — treat as done.
          @recorder.record(:thinking, { content: call.completion.content })
          return Result.new(stop_reason: :completed, iterations: iteration)
        end

        finished = run_tool_calls(tool_calls, messages)
        return Result.new(stop_reason: :completed, iterations: iteration) if finished
      end
    end

    private

    def run_tool_calls(tool_calls, messages)
      finished = false
      tool_calls.each do |tc|
        fn = tc.fetch("function")
        output = Tools.dispatch(
          name: fn["name"], arguments: fn["arguments"],
          workspace: @workspace, recorder: @recorder
        )
        finished ||= fn["name"] == Tools::FINISH
        messages << { role: "tool", tool_call_id: tc["id"], content: output.to_s }
      end
      finished
    end

    def record_call(call)
      completion = call.completion
      @recorder.record_llm_call(
        provider:      call.provider_name,
        model:         call.model,
        input_tokens:  completion.input_tokens,
        output_tokens: completion.output_tokens,
        cost_usd:      call.cost_usd,
        fallback:      call.fallback
      )
    end

    def assistant_message(completion)
      message = { role: "assistant", content: completion.content }
      message[:tool_calls] = completion.tool_calls if completion.tool_calls.present?
      message
    end

    def task_prompt
      parts = [ @run.name, @run.description ].compact_blank
      if (task = @run.linear_task)
        parts.unshift("#{task.code}: #{task.name}", task.description)
      end
      parts.compact_blank.join("\n\n").presence || "Improve the repository."
    end
  end
end
