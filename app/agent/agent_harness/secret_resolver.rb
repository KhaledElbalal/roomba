class AgentHarness
  # Resolves a `*_secret_ref` (an AWS Secrets Manager ARN or name) to its plain
  # secret string at runtime. The harness never persists or logs the resolved
  # value — only the ref lives in the database (FR: secrets never logged).
  class SecretResolver
    class SecretNotFound < StandardError; end

    def initialize(client: nil)
      # Lazily build the client so test/dev paths that never resolve a real
      # secret don't require AWS credentials at boot.
      @client = client
    end

    def resolve(secret_ref)
      raise SecretNotFound, "blank secret ref" if secret_ref.blank?

      resp = client.get_secret_value(secret_id: secret_ref)
      resp.secret_string.presence ||
        Base64.strict_decode64(resp.secret_binary)
    rescue Aws::SecretsManager::Errors::ServiceError => e
      # Deliberately interpolate the ref (not the value) — refs are non-secret.
      raise SecretNotFound, "could not resolve #{secret_ref}: #{e.class}"
    end

    private

    def client
      @client ||= Aws::SecretsManager::Client.new
    end
  end
end
