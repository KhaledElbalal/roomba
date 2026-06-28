class LlmProvider < ApplicationRecord
  has_many :runs, foreign_key: :llm_provider_id, dependent: :restrict_with_error
  has_many :fallback_runs, class_name: "Run", foreign_key: :llm_provider_fallback_id,
           dependent: :nullify

  validates :provider_name, presence: true

  scope :for_user, ->(uid) { where(user_id: uid) }
end
