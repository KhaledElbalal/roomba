class Run < ApplicationRecord
  self.table_name = "agent_runs"

  belongs_to :linear_task, optional: true
  belongs_to :llm_provider
  belongs_to :llm_provider_fallback, class_name: "LlmProvider",
             foreign_key: :llm_provider_fallback_id, optional: true
  has_many :artifacts, -> { order(:sequence) }, foreign_key: :agent_run_id, dependent: :destroy

  enum :status, { queued: "queued", running: "running", succeeded: "succeeded", failed: "failed" }

  scope :for_user, ->(uid) { where(user_id: uid) }
  scope :in_range, ->(r)   { where(created_at: r) }

  def self.filter_by(status: nil, repo: nil)
    rel = all
    rel = rel.where(status: status)    if status.present?
    rel = rel.where(github_repo: repo) if repo.present?
    rel
  end
end
