require "rails_helper"

RSpec.describe Run, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:llm_provider) }
    it { is_expected.to belong_to(:linear_task).optional }
    it { is_expected.to belong_to(:llm_provider_fallback).optional }
    it { is_expected.to have_many(:artifacts).order(:sequence).dependent(:destroy) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(queued: "queued", running: "running", succeeded: "succeeded", failed: "failed").backed_by_column_of_type(:string) }
  end

  describe ".for_user" do
    it "returns only runs belonging to the given user" do
      uid = SecureRandom.uuid
      provider = create(:llm_provider, user_id: uid)
      mine  = create(:run, user_id: uid, llm_provider: provider)
      _other = create(:run)

      expect(Run.for_user(uid)).to contain_exactly(mine)
    end
  end

  describe ".in_range" do
    it "returns runs whose created_at falls within the range" do
      inside  = create(:run, created_at: 3.days.ago)
      _outside = create(:run, created_at: 10.days.ago)

      expect(Run.in_range(5.days.ago..Time.current)).to contain_exactly(inside)
    end
  end

  describe ".filter_by" do
    let!(:queued_run)    { create(:run, status: :queued,    github_repo: "acme/api") }
    let!(:succeeded_run) { create(:run, status: :succeeded, github_repo: "acme/web") }

    it "filters by status" do
      expect(Run.filter_by(status: "queued")).to contain_exactly(queued_run)
    end

    it "filters by repo" do
      expect(Run.filter_by(repo: "acme/web")).to contain_exactly(succeeded_run)
    end

    it "returns all when no filters given" do
      expect(Run.filter_by).to contain_exactly(queued_run, succeeded_run)
    end
  end
end
