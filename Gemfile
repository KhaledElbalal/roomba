source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"

# JWT verification (Neon Auth JWKS) + CORS for the SPA frontend
gem "jwt"
gem "rack-cors"

# Background job queue (QUEUE_BACKEND=db path)
gem "solid_queue"

# AWS SDK — for SQS queue backend and ECS agent dispatch
gem "aws-sdk-sqs",              "~> 1.0"
gem "aws-sdk-ecs",              "~> 1.0"
gem "aws-sdk-secretsmanager",   "~> 1.0"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit",          require: false
  gem "brakeman",               require: false
  gem "rubocop-rails-omakase",  require: false
  gem "rspec-rails",            "~> 7.0"
  gem "factory_bot_rails"
  gem "shoulda-matchers",       "~> 6.0"
end
