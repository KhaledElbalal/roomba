require "rails_helper"

RSpec.describe AgentHarness::EditLoop do
  let(:run)      { create(:run) }
  let(:recorder) { AgentHarness::ArtifactRecorder.new(run) }
  let(:workspace) { instance_double(AgentHarness::Workspace) }

  # Replays scripted provider calls in order; raises if the loop over-runs the
  # script so an unbounded loop fails loudly instead of hanging.
  class ScriptedProviders
    def initialize(calls) = @calls = calls.dup
    def chat(messages:, tools:) = @calls.shift || raise("provider called more times than scripted")
  end

  def call_with_tools(tools, model: "gpt-4o", cost: "0.01")
    completion = AgentHarness::LlmClient::Completion.new(
      content: nil, tool_calls: tools, input_tokens: 10, output_tokens: 5, model: model
    )
    AgentHarness::ProviderChain::Call.new(
      completion: completion, provider_name: "openai", model: model,
      cost_usd: BigDecimal(cost), fallback: false
    )
  end

  def tool(name, args, id: SecureRandom.hex(3))
    { "id" => id, "function" => { "name" => name, "arguments" => args.to_json } }
  end

  def bounds(**over)
    defaults = { max_iterations: 50, max_wall_clock_seconds: nil, max_cost_usd: nil, clock: -> { 0.0 } }
    AgentHarness::Bounds.new(**defaults.merge(over))
  end

  it "records one llm_call per model call and one artifact per tool step, in sequence" do
    allow(workspace).to receive(:write_file)
    providers = ScriptedProviders.new([
      call_with_tools([ tool("edit_file", { path: "a.rb", content: "x" }) ]),
      call_with_tools([ tool("finish", { summary: "done" }) ])
    ])

    result = described_class.new(
      run: run, workspace: workspace, providers: providers, recorder: recorder, bounds: bounds
    ).call

    expect(result.stop_reason).to eq(:completed)
    types = run.artifacts.order(:sequence).pluck(:artifact_type)
    # llm_call, edit_file, llm_call, thinking(finish)
    expect(types).to eq(%w[llm_call edit_file llm_call thinking])
    expect(workspace).to have_received(:write_file).with("a.rb", "x")
  end

  it "stops with the bound reason when max_iterations is exhausted" do
    providers = ScriptedProviders.new([
      call_with_tools([ tool("run_command", { command: "true" }) ]),
      call_with_tools([ tool("run_command", { command: "true" }) ])
    ])
    allow(workspace).to receive(:run_command)
      .and_return(AgentHarness::CommandRunner::Result.new(stdout: "", stderr: "", exit_status: 0))

    result = described_class.new(
      run: run, workspace: workspace, providers: providers, recorder: recorder,
      bounds: bounds(max_iterations: 1)
    ).call

    expect(result.stop_reason).to eq(:max_iterations)
    expect(result.iterations).to eq(1)
  end

  it "stops on max_cost_usd once accumulated spend reaches the budget" do
    providers = ScriptedProviders.new([
      call_with_tools([ tool("run_command", { command: "true" }) ], cost: "0.10")
    ])
    allow(workspace).to receive(:run_command)
      .and_return(AgentHarness::CommandRunner::Result.new(stdout: "", stderr: "", exit_status: 0))

    result = described_class.new(
      run: run, workspace: workspace, providers: providers, recorder: recorder,
      bounds: bounds(max_cost_usd: BigDecimal("0.10"))
    ).call

    # First turn spends 0.10; the second turn's top-of-loop check trips the bound.
    expect(result.stop_reason).to eq(:max_cost_usd)
  end

  it "treats a prose answer (no tool calls) as completion" do
    completion = AgentHarness::LlmClient::Completion.new(
      content: "all done", tool_calls: [], input_tokens: 1, output_tokens: 1, model: "gpt-4o"
    )
    call = AgentHarness::ProviderChain::Call.new(
      completion: completion, provider_name: "openai", model: "gpt-4o",
      cost_usd: BigDecimal("0.01"), fallback: false
    )

    result = described_class.new(
      run: run, workspace: workspace, providers: ScriptedProviders.new([ call ]), recorder: recorder, bounds: bounds
    ).call

    expect(result.stop_reason).to eq(:completed)
  end
end
