class LinearTask < ApplicationRecord
  has_many :runs, dependent: :nullify

  enum :task_type, { feature: "feature", bugfix: "bugfix" }
end
