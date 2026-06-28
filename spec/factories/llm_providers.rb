FactoryBot.define do
  factory :llm_provider do
    user_id          { SecureRandom.uuid }
    provider_name    { "openai" }
    base_url         { "https://api.openai.com/v1" }
    api_key_secret_ref { "arn:aws:secretsmanager:us-east-1:123456789:secret:llm-key-abc123" }
    available_models { [ "gpt-4o", "gpt-4o-mini" ] }
  end
end
