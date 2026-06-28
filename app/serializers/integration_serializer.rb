# Explicit shape for integrations. Deliberately exposes only the provider and a
# connected flag — never `token_secret_ref` or the token itself.
class IntegrationSerializer
  def self.collection(integrations) = integrations.map { |i| new(i).as_json }

  def initialize(integration)
    @integration = integration
  end

  def as_json(*)
    { provider: @integration.provider, connected: true }
  end
end
