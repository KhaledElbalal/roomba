FactoryBot.define do
  factory :artifact do
    association :run, factory: :run, strategy: :create
    sequence(:sequence) { |n| n }
    artifact_type { :llm_call }
    payload       { { model: "gpt-4o", input_tokens: 100, output_tokens: 50 } }
  end
end
