require "rails_helper"

RSpec.describe Metrics::CostQuery do
  let(:user_id) { SecureRandom.uuid }
  let(:range)   { 30.days.ago.. }

  def call(group_by: nil)
    described_class.new(user_id: user_id, range: range, group_by: group_by).call
  end

  it "returns the four cost keys" do
    expect(call.keys).to contain_exactly(:total_usd, :total_tokens, :by_group, :fallback_share)
  end

  context "with no runs" do
    it "returns zeros, empty group, and nil fallback_share" do
      expect(call[:total_usd]).to eq(0.0)
      expect(call[:total_tokens]).to eq(0)
      expect(call[:by_group]).to eq([])
      expect(call[:fallback_share]).to be_nil
    end
  end

  context "with runs" do
    let(:provider)  { create(:llm_provider, user_id: user_id, provider_name: "openai") }
    let(:provider2) { create(:llm_provider, user_id: user_id, provider_name: "anthropic") }

    before do
      create(:run, :succeeded, user_id: user_id, llm_provider: provider,
             cost_usd: 1.5, tokens_used: 10_000)
      create(:run, :succeeded, user_id: user_id, llm_provider: provider2,
             cost_usd: 0.5, tokens_used: 5_000)
    end

    it "sums total_usd and total_tokens across all runs" do
      expect(call[:total_usd]).to be_within(0.001).of(2.0)
      expect(call[:total_tokens]).to eq(15_000)
    end

    it "groups by provider" do
      groups = call(group_by: "provider")[:by_group]
      keys   = groups.map { |g| g[:key] }

      expect(keys).to contain_exactly("openai", "anthropic")
      openai_group = groups.find { |g| g[:key] == "openai" }
      expect(openai_group[:spend_usd]).to be_within(0.001).of(1.5)
      expect(openai_group[:tokens]).to eq(10_000)
    end

    it "returns empty by_group when group_by is omitted" do
      expect(call[:by_group]).to eq([])
    end

    it "returns empty by_group for an unknown group_by value" do
      expect(call(group_by: "unknown")[:by_group]).to eq([])
    end

    context "fallback_share" do
      it "is 0 when no run has a fallback configured" do
        expect(call[:fallback_share]).to eq(0.0)
      end

      it "counts runs with a fallback provider configured" do
        fallback = create(:llm_provider, user_id: user_id)
        create(:run, :succeeded, user_id: user_id, llm_provider: provider,
               llm_provider_fallback: fallback, cost_usd: 0, tokens_used: 0)

        result = call
        # 1 of 3 runs has a fallback configured
        expect(result[:fallback_share]).to be_within(0.001).of(1.0 / 3)
      end
    end
  end

  context "group_by model from llm_call artifacts" do
    let(:provider) { create(:llm_provider, user_id: user_id) }

    before do
      run = create(:run, :succeeded, user_id: user_id, llm_provider: provider,
                   cost_usd: 2.0, tokens_used: 15_000)
      create(:artifact, run: run, artifact_type: :llm_call,
             payload: { model: "gpt-4o", input_tokens: 100, output_tokens: 50 })
      create(:artifact, run: run, artifact_type: :llm_call,
             payload: { model: "gpt-4o-mini", input_tokens: 40, output_tokens: 20 })
    end

    it "groups artifacts by model and sums tokens" do
      groups = call(group_by: "model")[:by_group]
      keys   = groups.map { |g| g[:key] }

      expect(keys).to contain_exactly("gpt-4o", "gpt-4o-mini")
      gpt4o = groups.find { |g| g[:key] == "gpt-4o" }
      expect(gpt4o[:tokens]).to eq(150)
      expect(gpt4o[:spend_usd]).to be_nil
    end
  end

  context "user scoping" do
    let(:other_user) { SecureRandom.uuid }
    let(:provider)   { create(:llm_provider, user_id: other_user) }

    it "excludes runs from other users" do
      create(:run, :succeeded, user_id: other_user, llm_provider: provider,
             cost_usd: 99.0, tokens_used: 999_999)

      expect(call[:total_usd]).to eq(0.0)
    end
  end
end
