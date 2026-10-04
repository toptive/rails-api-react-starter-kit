Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  constraints OperationsAccess do
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end

  namespace :api do
    namespace :v1 do
      resource :health, only: :show, controller: :health
    end
    match "*path", to: "errors#show", via: :all
    match "/", to: "errors#show", via: :all
  end
end
