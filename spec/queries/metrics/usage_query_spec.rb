require "rails_helper"

RSpec.describe Metrics::UsageQuery do
  let(:user_id) { SecureRandom.uuid }
  let(:range)   { 30.days.ago.. }

  subject(:result) { described_class.new(user_id: user_id, range: range).call }

  it "returns the three usage keys" do
    expect(result.keys).to contain_exactly(
      :run_count, :success_rate, :queue_wait_median_seconds
    )
  end

  context "with no runs" do
    it "returns zeros and nils" do
      expect(result[:run_count]).to eq(0)
      expect(result[:success_rate]).to be_nil
      expect(result[:queue_wait_median_seconds]).to be_nil
    end
  end

  context "with a mix of succeeded and failed runs" do
    let(:provider) { create(:llm_provider, user_id: user_id) }

    before do
      create(:run, :succeeded, user_id: user_id, llm_provider: provider)
      create(:run, :succeeded, user_id: user_id, llm_provider: provider)
      create(:run, :failed,    user_id: user_id, llm_provider: provider)
    end

    it "counts all runs" do
      expect(result[:run_count]).to eq(3)
    end

    it "computes success_rate as succeeded / total" do
      expect(result[:success_rate]).to be_within(0.001).of(2.0 / 3)
    end
  end

  context "queue_wait_median_seconds" do
    let(:provider) { create(:llm_provider, user_id: user_id) }

    it "is the median wait from created_at to started_at" do
      create(:run, :succeeded, user_id: user_id, llm_provider: provider,
             created_at: 10.minutes.ago, started_at: 8.minutes.ago)
      create(:run, :succeeded, user_id: user_id, llm_provider: provider,
             created_at: 10.minutes.ago, started_at: 6.minutes.ago)

      expect(result[:queue_wait_median_seconds]).to be > 0
    end
  end

  context "user scoping" do
    let(:other_user) { SecureRandom.uuid }
    let(:provider)   { create(:llm_provider, user_id: other_user) }

    it "excludes runs from other users" do
      create(:run, :succeeded, user_id: other_user, llm_provider: provider)

      expect(result[:run_count]).to eq(0)
    end
  end
end
