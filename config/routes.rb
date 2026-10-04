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
      resources :email_subscriptions, path: "email-subscriptions", only: :show, param: :token do
        resource :opt_out, path: "opt-out", only: :create, controller: :email_opt_outs
      end
      resource :current_organization, path: "current-organization", only: [] do
        put "", action: :update, as: :update
      end
      resources :organizations, only: :create
      resource :onboarding, only: :show do
        put "", action: :update, as: :update
      end
      resources :invitations, only: :show, param: :token do
        resource :acceptance, only: :create, controller: :invitation_acceptances
      end
      namespace :settings do
        resource :profile, only: [] do
          put "", action: :update, as: :update
        end
        resource :email_preferences, path: "email-preferences", only: :show do
          put "", action: :update, as: :update
        end
        resources :sessions, only: %i[index destroy]
        resource :email, only: [] do
          put "", action: :update, as: :update
        end
        resources :email_confirmations, path: "email-confirmations", param: :token, only: %i[show create]
        resource :password, only: [] do
          put "", action: :update, as: :update
        end
        resource :account, only: %i[show destroy]
        resource :organization, only: :show do
          put "", action: :update, as: :update
        end
        resources :members, only: %i[index destroy] do
          put "", action: :update, on: :member, as: :update
        end
        resources :invitations, only: %i[index create destroy]
      end
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
