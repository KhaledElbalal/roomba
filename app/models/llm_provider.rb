class LlmProvider < ApplicationRecord
  has_many :runs, foreign_key: :llm_provider_id, dependent: :restrict_with_error
  has_many :fallback_runs, class_name: "Run", foreign_key: :llm_provider_fallback_id,
           dependent: :nullify

  scope :for_user, ->(uid) { where(user_id: uid) }
end
