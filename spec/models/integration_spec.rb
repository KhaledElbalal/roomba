require "rails_helper"

RSpec.describe Integration, type: :model do
  describe "enums" do
    it { is_expected.to define_enum_for(:provider).with_values(github: "github", linear: "linear").backed_by_column_of_type(:string) }
  end

  describe ".for_user" do
    it "returns only integrations belonging to the given user" do
      uid   = SecureRandom.uuid
      mine  = create(:integration, user_id: uid)
      _other = create(:integration)

      expect(Integration.for_user(uid)).to contain_exactly(mine)
    end
  end

  describe "uniqueness" do
    it "rejects duplicate provider per user" do
      uid = SecureRandom.uuid
      create(:integration, user_id: uid, provider: :github)
      dup = build(:integration, user_id: uid, provider: :github)

      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
