require "rails_helper"

RSpec.describe AgentHarness::Bounds do
  def bounds(iterations: nil, seconds: nil, cost: nil, clock: -> { 0.0 })
    described_class.new(
      max_iterations: iterations, max_wall_clock_seconds: seconds,
      max_cost_usd: cost, clock: clock
    )
  end

  it "returns nil while every bound has headroom" do
    b = bounds(iterations: 5, seconds: 60, cost: 1.0).start!
    expect(b.breach(iteration: 2, cost_usd: BigDecimal("0.5"))).to be_nil
  end

  it "trips max_iterations at the limit" do
    b = bounds(iterations: 3).start!
    expect(b.breach(iteration: 3, cost_usd: BigDecimal(0))).to eq(:max_iterations)
  end

  it "trips max_cost_usd at the limit" do
    b = bounds(cost: BigDecimal("0.10")).start!
    expect(b.breach(iteration: 0, cost_usd: BigDecimal("0.10"))).to eq(:max_cost_usd)
  end

  it "trips max_wall_clock_seconds once the clock advances past the budget" do
    time = 100.0
    b = bounds(seconds: 30, clock: -> { time }).start!
    expect(b.breach(iteration: 0, cost_usd: BigDecimal(0))).to be_nil
    time = 131.0
    expect(b.breach(iteration: 0, cost_usd: BigDecimal(0))).to eq(:max_wall_clock_seconds)
  end

  it "treats nil bounds as unbounded" do
    b = bounds.start!
    expect(b.breach(iteration: 10_000, cost_usd: BigDecimal("999"))).to be_nil
  end

  it "reports iterations before wall clock when both are exhausted" do
    b = bounds(iterations: 1, seconds: 0, clock: -> { 0.0 }).start!
    expect(b.breach(iteration: 1, cost_usd: BigDecimal(0))).to eq(:max_iterations)
  end
end
