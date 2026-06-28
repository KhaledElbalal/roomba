module Api
  class IntegrationsController < Api::BaseController
    rescue_from ProviderValidation::Error, with: :unprocessable

    def index
      render json: IntegrationSerializer.collection(Integration.for_user(current_user_id))
    end

    def create
      provider = params.require(:provider)
      token    = params.require(:token)

      metadata = ProviderValidation.for(provider).call(token)
      ref      = Secrets.new.put(name: secret_name(provider), value: token)

      integration = Integration.for_user(current_user_id).find_or_initialize_by(provider: provider)
      integration.update!(token_secret_ref: ref, metadata: metadata)

      render json: IntegrationSerializer.new(integration).as_json, status: :created
    end

    def destroy
      # Querying the enum with an unknown value raises ArgumentError, so reject
      # anything that isn't a real provider as a plain 404.
      raise ActiveRecord::RecordNotFound unless Integration.providers.key?(params[:provider])

      integration = Integration.for_user(current_user_id).find_by!(provider: params[:provider])
      # Drop the row first, then the secret: a row without its secret is
      # recoverable (re-connect), but an orphaned secret is invisible to the user.
      ref = integration.token_secret_ref
      integration.destroy!
      Secrets.new.delete(ref)

      head :no_content
    end

    private

    def secret_name(provider)
      "roomba/integrations/#{current_user_id}/#{provider}"
    end

    def unprocessable(error)
      render json: { error: error.message }, status: :unprocessable_content
    end
  end
end
