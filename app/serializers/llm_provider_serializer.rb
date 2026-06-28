# Explicit shape for llm_providers. Whitelists config fields only; never exposes
# `api_key_secret_ref` or the key.
class LlmProviderSerializer
  def self.collection(providers) = providers.map { |p| new(p).as_json }

  def initialize(provider)
    @provider = provider
  end

  def as_json(*)
    {
      id:               @provider.id,
      provider_name:    @provider.provider_name,
      base_url:         @provider.base_url,
      available_models: @provider.available_models
    }
  end
end
