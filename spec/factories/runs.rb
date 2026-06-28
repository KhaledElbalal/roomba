FactoryBot.define do
  factory :run do
    user_id     { SecureRandom.uuid }
    github_repo { "acme/api" }
    status      { :queued }
    association :llm_provider

    trait :running do
      status     { :running }
      started_at { Time.current }
    end
    trait :succeeded do
      status      { :succeeded }
      started_at  { 5.minutes.ago }
      finished_at { 1.minute.ago }
    end
    trait :failed do
      status         { :failed }
      started_at     { 10.minutes.ago }
      finished_at    { 5.minutes.ago }
      failure_reason { "Agent exceeded max_iterations" }
    end

    trait :deployed do
      status        { :succeeded }
      started_at    { 30.minutes.ago }
      finished_at   { 20.minutes.ago }
      pr_opened_at  { 35.minutes.ago }
      deployed_at   { 15.minutes.ago }
    end

    trait :with_linear_task do
      association :linear_task
    end

    trait :with_fallback do
      association :llm_provider_fallback, factory: :llm_provider
    end
  end
end
