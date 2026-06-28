require "rails_helper"

RSpec.describe AgentHarness::Pricing do
  it "prices a known model from its per-million rates" do
    # 1M input @ $2.50 + 1M output @ $10.00
    cost = described_class.cost(model: "gpt-4o", input_tokens: 1_000_000, output_tokens: 1_000_000)
    expect(cost).to eq(BigDecimal("12.5"))
  end

  it "prorates fractional token counts" do
    cost = described_class.cost(model: "gpt-4o-mini", input_tokens: 1_000, output_tokens: 500)
    # 1000 * 0.15/1e6 + 500 * 0.60/1e6
    expect(cost).to eq(BigDecimal("0.00045"))
  end

  it "falls back to DEFAULT rates for unknown models" do
    cost = described_class.cost(model: "mystery-1", input_tokens: 1_000_000, output_tokens: 0)
    expect(cost).to eq(BigDecimal(AgentHarness::Pricing::DEFAULT[:input].to_s))
  end

  it "returns a BigDecimal" do
    expect(described_class.cost(model: "gpt-4o", input_tokens: 1, output_tokens: 1)).to be_a(BigDecimal)
  end
end
