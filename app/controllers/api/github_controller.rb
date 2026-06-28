module Api
  class GithubController < Api::BaseController
    def repos
      token = IntegrationToken.resolve(user_id: current_user_id, provider: :github)
      render json: ProviderProxy::GithubRepos.call(token)
    end
  end
end
