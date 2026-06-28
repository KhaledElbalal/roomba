FactoryBot.define do
  factory :linear_task do
    sequence(:code) { |n| "ROO-#{n}" }
    name      { "Add dark mode toggle" }
    task_type { :feature }
    synced_at { Time.current }
  end
end
