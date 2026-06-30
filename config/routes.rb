Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    get "me", to: "me#show"

    resources :runs, only: [ :index, :show, :create ] do
      resources :artifacts, only: [ :index ]
    end

    # PAT integrations are addressed by provider, not id (unique per user).
    resources :integrations, only: [ :index, :create, :destroy ], param: :provider

    resources :llm_providers, only: [ :index, :create, :update, :destroy ]

    # Read-through pickers: list a user's Linear issues / GitHub repos via their
    # stored PAT so the frontend can point a run at a target.
    get "linear/issues", to: "linear#issues"
    get "github/repos",  to: "github#repos"

    namespace :metrics do
      get :dora
      get :usage
      get :cost
      get :timeseries
    end
  end
end
