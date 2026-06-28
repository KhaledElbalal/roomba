require "rails_helper"

RSpec.describe Metrics::TimeseriesQuery do
  let(:user_id) { SecureRandom.uuid }
  let(:range)   { 30.days.ago.. }

  def call(metric: "run_count", interval: "day")
    described_class.new(user_id: user_id, range: range, metric: metric, interval: interval).call
  end

  it "returns metric, interval, and points keys" do
    expect(call.keys).to contain_exactly(:metric, :interval, :points)
  end

  it "defaults to run_count / day when params are unknown" do
    result = described_class.new(user_id: user_id, range: range,
                                 metric: "nonsense", interval: "year").call
    expect(result[:metric]).to eq("run_count")
    expect(result[:interval]).to eq("day")
  end

  context "with runs on different days" do
    let(:provider) { create(:llm_provider, user_id: user_id) }

    before do
      travel_to(2.days.ago) do
        create(:run, :succeeded, user_id: user_id, llm_provider: provider, cost_usd: 1.0, tokens_used: 100)
        create(:run, :succeeded, user_id: user_id, llm_provider: provider, cost_usd: 2.0, tokens_used: 200)
      end
      travel_to(1.day.ago) do
        create(:run, :succeeded, user_id: user_id, llm_provider: provider, cost_usd: 3.0, tokens_used: 300)
      end
    end

    it "counts runs per day" do
      points = call(metric: "run_count")[:points]
      counts = points.map { |p| p[:value] }

      expect(counts).to include(2, 1)
      expect(points.map { |p| p[:date] }).to all(match(/\A\d{4}-\d{2}-\d{2}\z/))
    end

    it "sums cost_usd per day" do
      points = call(metric: "cost_usd")[:points]
      values = points.map { |p| p[:value].to_f }

      expect(values).to include(be_within(0.001).of(3.0), be_within(0.001).of(3.0))
    end

    it "sums tokens_used per day" do
      points = call(metric: "tokens_used")[:points]
      values = points.map { |p| p[:value].to_i }

      expect(values).to include(300, 300)
    end
  end

  context "user scoping" do
    let(:other_user) { SecureRandom.uuid }
    let(:provider)   { create(:llm_provider, user_id: other_user) }

    it "excludes runs from other users" do
      create(:run, :succeeded, user_id: other_user, llm_provider: provider)

      expect(call[:points]).to eq([])
    end
  end
end
