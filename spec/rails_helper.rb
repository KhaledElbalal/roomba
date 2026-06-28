require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
ENV['NEON_AUTH_JWKS_URL'] ||= 'https://neon-auth.example.test/.well-known/jwks.json'
ENV['NEON_AUTH_ISSUER']   ||= 'https://neon-auth.example.test'
ENV['NEON_AUTH_AUDIENCE'] ||= 'roomba'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
Shoulda::Matchers.configure do |config|
  config.integrate { |with| with.test_framework(:rspec); with.library(:rails) }
end

require 'jwt'
require 'openssl'
Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  config.include AuthHelpers, type: :request

  config.fixture_paths = [
    Rails.root.join('spec/fixtures')
  ]

  config.use_transactional_fixtures = true

  config.filter_rails_from_backtrace!
end
