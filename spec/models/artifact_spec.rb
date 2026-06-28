require "rails_helper"

RSpec.describe Artifact, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:run) }
  end

  describe "enums" do
    it {
      is_expected.to define_enum_for(:artifact_type)
        .with_values(thinking: "thinking", read_file: "read_file", edit_file: "edit_file",
                     run_command: "run_command", llm_call: "llm_call")
        .backed_by_column_of_type(:string)
    }
  end

  describe "table" do
    it "persists to agent_artifacts" do
      expect(described_class.table_name).to eq("agent_artifacts")
    end
  end
end
