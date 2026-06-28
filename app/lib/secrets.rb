# Single source of truth for AWS Secrets Manager access. Only the returned
# reference (ARN) is ever persisted; the plaintext value lives here in memory
# and is never logged. Both the integrations/llm_providers write path and the
# agent runner read path go through this wrapper (FR: secrets never logged).
class Secrets
  class Error < StandardError; end
  class NotFound < Error; end

  def initialize(client: nil)
    # Build the client lazily so test/dev paths that stub this PORO never
    # require AWS credentials at boot.
    @client = client
  end

  # Store a value, returning its stable reference. Pass `ref:` to rotate an
  # existing secret in place (keeps the same ARN, so persisted refs stay valid);
  # otherwise creates-or-updates by `name:`.
  def put(value:, name: nil, ref: nil)
    return client.put_secret_value(secret_id: ref, secret_string: value).arn if ref.present?

    raise ArgumentError, "name or ref required" if name.blank?

    create_or_update(name, value)
  end

  def get(ref)
    raise NotFound, "blank secret ref" if ref.blank?

    resp = client.get_secret_value(secret_id: ref)
    resp.secret_string.presence || Base64.strict_decode64(resp.secret_binary)
  rescue Aws::SecretsManager::Errors::ResourceNotFoundException => e
    # Interpolate the ref (non-secret), never the value.
    raise NotFound, "could not resolve #{ref}: #{e.class}"
  end

  def delete(ref)
    return if ref.blank?

    # force_delete skips the recovery window so a later re-connect can reuse the
    # name immediately instead of hitting "scheduled for deletion".
    client.delete_secret(secret_id: ref, force_delete_without_recovery: true)
    nil
  rescue Aws::SecretsManager::Errors::ResourceNotFoundException
    nil # already gone — deletion is idempotent
  end

  private

  def create_or_update(name, value)
    client.create_secret(name: name, secret_string: value).arn
  rescue Aws::SecretsManager::Errors::ResourceExistsException
    client.put_secret_value(secret_id: name, secret_string: value).arn
  end

  def client
    @client ||= Aws::SecretsManager::Client.new
  end
end
