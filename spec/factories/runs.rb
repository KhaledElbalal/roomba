FactoryBot.define do
  factory :run do
    user_id     { SecureRandom.uuid }
    github_repo { "acme/api" }
    status      { :queued }
    association :llm_provider

    trait :running  do status { :running }   end
    trait :succeeded do status { :succeeded } end
    trait :failed   do
      status         { :failed }
      failure_reason { "Agent exceeded max_iterations" }
    end

    trait :with_linear_task do
      association :linear_task
    end
  end
end
