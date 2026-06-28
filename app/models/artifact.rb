class Artifact < ApplicationRecord
  self.table_name = "agent_artifacts"

  belongs_to :run, foreign_key: :agent_run_id

  enum :artifact_type, {
    thinking:    "thinking",
    read_file:   "read_file",
    edit_file:   "edit_file",
    run_command: "run_command",
    llm_call:    "llm_call"
  }
end
