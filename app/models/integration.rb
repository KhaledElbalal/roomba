class Integration < ApplicationRecord
  enum :provider, { github: "github", linear: "linear" }

  scope :for_user, ->(uid) { where(user_id: uid) }
end
