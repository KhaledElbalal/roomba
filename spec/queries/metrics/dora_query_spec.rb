require "rails_helper"

RSpec.describe Metrics::DoraQuery do
  let(:user_id) { SecureRandom.uuid }
  let(:range)   { 30.days.ago.. }

  subject(:result) { described_class.new(user_id: user_id, range: range).call }

  it "returns all four DORA keys" do
    expect(result.keys).to contain_exactly(
      :lead_time_median_seconds, :deployment_frequency,
      :change_failure_rate, :mttr_seconds
    )
  end

  context "with no runs" do
    it "returns nil for each scalar metric and empty frequency" do
      expect(result[:lead_time_median_seconds]).to be_nil
      expect(result[:deployment_frequency]).to eq({})
      expect(result[:change_failure_rate]).to be_nil
      expect(result[:mttr_seconds]).to be_nil
    end
  end

  context "with deployed runs" do
    let(:provider) { create(:llm_provider, user_id: user_id) }

    before do
      create(:run, :deployed, user_id: user_id, llm_provider: provider,
             pr_opened_at: 2.hours.ago, deployed_at: 1.hour.ago)
      create(:run, :deployed, user_id: user_id, llm_provider: provider,
             pr_opened_at: 3.hours.ago, deployed_at: 1.hour.ago)
    end

    it "computes a positive lead_time_median_seconds" do
      expect(result[:lead_time_median_seconds]).to be > 0
    end

    it "includes deploy counts keyed by date string" do
      expect(result[:deployment_frequency].keys).to all(match(/\A\d{4}-\d{2}-\d{2}\z/))
      expect(result[:deployment_frequency].values).to all(be_an(Integer))
    end
  end

  context "change_failure_rate" do
    let(:provider) { create(:llm_provider, user_id: user_id) }

    it "is nil when there are no deployed runs" do
      expect(result[:change_failure_rate]).to be_nil
    end

    it "returns fraction of deployed runs with changes_requested" do
      create(:run, :deployed, user_id: user_id, llm_provider: provider, changes_requested: true)
      create(:run, :deployed, user_id: user_id, llm_provider: provider, changes_requested: false)

      expect(result[:change_failure_rate]).to eq(0.5)
    end
  end

  context "mttr_seconds" do
    let(:provider) { create(:llm_provider, user_id: user_id) }

    it "computes median duration of failed runs" do
      create(:run, :failed, user_id: user_id, llm_provider: provider,
             started_at: 20.minutes.ago, finished_at: 10.minutes.ago)

      expect(result[:mttr_seconds]).to be > 0
    end
  end

  context "user scoping" do
    let(:other_user) { SecureRandom.uuid }
    let(:provider)   { create(:llm_provider, user_id: other_user) }

    it "does not count runs belonging to another user" do
      create(:run, :deployed, user_id: other_user, llm_provider: provider)

      expect(result[:deployment_frequency]).to eq({})
      expect(result[:change_failure_rate]).to be_nil
    end
  end
end
