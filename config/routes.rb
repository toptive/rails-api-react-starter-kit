Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  constraints OperationsAccess do
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end

  namespace :api do
    namespace :v1 do
      resource :health, only: :show, controller: :health
      resource :bootstrap, only: :show
      resources :locales, only: :show, param: :locale
      namespace :auth do
        resources :registrations, only: :create
        resources :magic_links, path: "magic-links", param: :token, only: %i[create show] do
          resource :session, only: :create, controller: :magic_link_sessions
        end
        resources :sessions, only: :create
        resource :session, only: :destroy
        resource :sudo, only: :create, controller: :sudos
        resource :impersonation, only: :destroy
      end
      namespace :admin do
        resource :jobs_access, path: "jobs-access", only: :create, controller: :jobs_accesses
      end
    end
    match "*path", to: "errors#show", via: :all
    match "/", to: "errors#show", via: :all
  end
end
