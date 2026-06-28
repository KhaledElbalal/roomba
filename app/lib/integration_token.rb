# Resolves a user's stored PAT for a provider at call time: looks up the
# integration row, then reads the plaintext from Secrets Manager via its ref.
# The token never lives in the DB, so this is the only path that materializes
# it. A missing row — or a ref whose secret has been deleted out of band —
# means the user must (re)connect, surfaced as ProviderProxy::NotConnected.
class IntegrationToken
  def self.resolve(user_id:, provider:, secrets: Secrets.new)
    integration = Integration.for_user(user_id).find_by(provider: provider)
    raise ProviderProxy::NotConnected, provider if integration.nil?

    secrets.get(integration.token_secret_ref)
  rescue Secrets::NotFound
    raise ProviderProxy::NotConnected, provider
  end
end
