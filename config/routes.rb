Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    get "me", to: "me#show"

    namespace :metrics do
      get :dora
      get :usage
      get :cost
      get :timeseries
    end
  end
end
