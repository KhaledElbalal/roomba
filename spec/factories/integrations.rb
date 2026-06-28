FactoryBot.define do
  factory :integration do
    user_id          { SecureRandom.uuid }
    provider         { :github }
    token_secret_ref { "arn:aws:secretsmanager:us-east-1:123456789:secret:gh-pat-abc123" }
    metadata         { {} }

    trait :linear do
      provider         { :linear }
      token_secret_ref { "arn:aws:secretsmanager:us-east-1:123456789:secret:linear-pat-abc123" }
    end
  end
end
