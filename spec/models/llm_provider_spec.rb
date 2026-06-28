require "rails_helper"

RSpec.describe LlmProvider, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:runs) }
    it { is_expected.to have_many(:fallback_runs) }
  end

  describe ".for_user" do
    it "returns only providers belonging to the given user" do
      uid   = SecureRandom.uuid
      mine  = create(:llm_provider, user_id: uid)
      _other = create(:llm_provider)

      expect(LlmProvider.for_user(uid)).to contain_exactly(mine)
    end
  end
end
