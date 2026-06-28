require "rails_helper"

RSpec.describe LinearTask, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:runs) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:task_type).with_values(feature: "feature", bugfix: "bugfix").backed_by_column_of_type(:string) }
  end

  describe "uniqueness" do
    it "rejects duplicate codes" do
      create(:linear_task, code: "ROO-42")
      dup = build(:linear_task, code: "ROO-42")

      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
