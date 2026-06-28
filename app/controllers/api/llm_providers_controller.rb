module Api
  class LlmProvidersController < Api::BaseController
    rescue_from ProviderValidation::Error, with: :unprocessable
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable

    def index
      render json: LlmProviderSerializer.collection(LlmProvider.for_user(current_user_id))
    end

    def create
      api_key = params.require(:api_key)
      attrs   = provider_params

      LlmKeyValidator.call(base_url: attrs[:base_url], api_key: api_key)
      ref = Secrets.new.put(name: secret_name, value: api_key)

      provider = LlmProvider.create!(
        attrs.merge(user_id: current_user_id, api_key_secret_ref: ref)
      )

      render json: LlmProviderSerializer.new(provider).as_json, status: :created
    end

    def update
      provider = LlmProvider.for_user(current_user_id).find(params[:id])
      attrs    = provider_params

      if (api_key = params[:api_key]).present?
        LlmKeyValidator.call(base_url: attrs[:base_url] || provider.base_url, api_key: api_key)
        # Rotate in place so the persisted ref stays valid.
        Secrets.new.put(ref: provider.api_key_secret_ref, value: api_key)
      end

      provider.update!(attrs)
      render json: LlmProviderSerializer.new(provider).as_json
    end

    def destroy
      provider = LlmProvider.for_user(current_user_id).find(params[:id])
      provider.destroy!
      Secrets.new.delete(provider.api_key_secret_ref)

      head :no_content
    end

    private

    def provider_params
      params.permit(:provider_name, :base_url, available_models: []).to_h.symbolize_keys
    end

    def secret_name
      "roomba/llm_providers/#{current_user_id}/#{SecureRandom.uuid}"
    end

    def unprocessable(error)
      render json: { error: error.message }, status: :unprocessable_entity
    end
  end
end
