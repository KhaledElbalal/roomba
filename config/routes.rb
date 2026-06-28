Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    get "me", to: "me#show"

    # PAT integrations are addressed by provider, not id (unique per user).
    resources :integrations, only: [ :index, :create, :destroy ], param: :provider

    resources :llm_providers, only: [ :index, :create, :update, :destroy ]

    namespace :metrics do
      get :dora
      get :usage
      get :cost
      get :timeseries
    end
  end
end
