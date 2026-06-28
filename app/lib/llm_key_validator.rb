# Validates an LLM provider API key with a cheap call (GET {base_url}/models,
# the OpenAI-compatible listing every supported provider exposes). Raises
# ProviderValidation::Error on rejection so the controller can return 422
# without echoing the key. When no base_url is known there is nothing cheap to
# call, so we accept and let the first real run surface a bad key.
class LlmKeyValidator
  def self.call(base_url:, api_key:, http: ProviderValidation.adapter)
    new(http).call(base_url: base_url, api_key: api_key)
  end

  def initialize(http)
    @http = http
  end

  def call(base_url:, api_key:)
    return true if base_url.blank?

    uri = URI.join("#{base_url.chomp('/')}/", "models")
    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Bearer #{api_key}"

    resp = @http.request(uri, req)
    unless resp.is_a?(Net::HTTPSuccess)
      raise ProviderValidation::Error, "provider rejected the API key (HTTP #{resp.code})"
    end

    true
  rescue ProviderValidation::Error
    raise
  rescue => e
    raise ProviderValidation::Error, "could not reach provider: #{e.class}"
  end
end
