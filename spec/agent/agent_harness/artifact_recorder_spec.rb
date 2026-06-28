require "rails_helper"

RSpec.describe AgentHarness::ArtifactRecorder do
  let(:run) { create(:run) }

  subject(:recorder) { described_class.new(run) }

  it "assigns monotonically increasing sequence numbers" do
    recorder.record(:thinking, { note: "a" })
    recorder.record(:read_file, { path: "x" })

    expect(run.artifacts.order(:sequence).pluck(:sequence)).to eq([ 1, 2 ])
  end

  it "continues the sequence after existing artifacts (resume-safe)" do
    create(:artifact, run: run, sequence: 7, artifact_type: :thinking)
    recorder = described_class.new(run)

    recorder.record(:read_file, { path: "x" })
    expect(run.artifacts.maximum(:sequence)).to eq(8)
  end

  it "accumulates cost and tokens across llm_call artifacts" do
    recorder.record_llm_call(provider: "openai", model: "gpt-4o",
      input_tokens: 100, output_tokens: 50, cost_usd: BigDecimal("0.01"), fallback: false)
    recorder.record_llm_call(provider: "together", model: "gpt-4o-mini",
      input_tokens: 200, output_tokens: 80, cost_usd: BigDecimal("0.02"), fallback: true)

    expect(recorder.total_cost_usd).to eq(BigDecimal("0.03"))
    expect(recorder.total_tokens).to eq(430)
  end

  it "writes the fallback flag and cost onto the llm_call payload" do
    recorder.record_llm_call(provider: "together", model: "gpt-4o-mini",
      input_tokens: 1, output_tokens: 2, cost_usd: BigDecimal("0.005"), fallback: true)

    artifact = run.artifacts.find_by(artifact_type: "llm_call")
    expect(artifact.payload).to include(
      "provider" => "together", "model" => "gpt-4o-mini",
      "fallback" => true, "cost_usd" => "0.005"
    )
  end
end
