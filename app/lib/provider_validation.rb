# Validates pasted credentials against the provider with a lightweight call
# before we ever store them. A failure raises ProviderValidation::Error, whose
# message is safe to surface to the user (it never echoes the token/key).
module ProviderValidation
  class Error < StandardError; end

  # Default per-call timeout; a stuck provider should not hang a request.
  HTTP_TIMEOUT = 15

  def self.for(provider)
    case provider.to_s
    when "github" then Github
    when "linear" then Linear
    else raise Error, "unknown provider: #{provider}"
    end
  end

  # Reuse the harness's tested Net::HTTP seam so specs can inject a fake.
  def self.adapter = AgentHarness::LlmClient::HttpAdapter.new(HTTP_TIMEOUT)
end
