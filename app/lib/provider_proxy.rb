# Read-through proxy to a user's connected providers (Linear, GitHub). Unlike
# ProviderValidation (which checks a freshly pasted token before we store it),
# this fetches resources with an already-stored token so the frontend can build
# pickers. Every failure carries an HTTP status so a revoked token or rate limit
# surfaces as 4xx/502 — never a bare 500.
module ProviderProxy
  class Error < StandardError
    attr_reader :status

    def initialize(message, status:)
      super(message)
      @status = status
    end
  end

  # The provider isn't linked for this user — the frontend should prompt a
  # connect, so this is a 409 rather than a transport/auth failure.
  class NotConnected < Error
    def initialize(provider)
      super("#{provider} is not connected", status: :conflict)
    end
  end

  HTTP_TIMEOUT = 15

  # Reuse the harness's tested Net::HTTP seam so specs can inject a fake.
  def self.adapter = AgentHarness::LlmClient::HttpAdapter.new(HTTP_TIMEOUT)
end
