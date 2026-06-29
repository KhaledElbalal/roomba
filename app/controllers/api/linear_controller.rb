module Api
  class LinearController < Api::BaseController
    def issues
      token = IntegrationToken.resolve(user_id: current_user_id, provider: :linear)
      render json: ProviderProxy::LinearIssues.call(token)
    end
  end
end
