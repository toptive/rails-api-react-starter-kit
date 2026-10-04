Rails.application.routes.draw do
  if Rails.env.test? && ENV["E2E"] == "1"
    get "/dev/mailbox", to: "dev/mailbox#show"
    get "/dev/mailbox/json", to: "dev/mailbox#show"
    post "/dev/mailbox/clear", to: "dev/mailbox#create"
  end

  resource :health, only: :show, controller: :health
  resource :sitemap, path: "sitemap.xml", only: :show, controller: :sitemaps
  resource :robots, path: "robots.txt", only: :show, controller: :robots
  get "up" => "rails/health#show", as: :rails_health_check
  namespace :admin do
    namespace :jobs do
      resource :session, only: :show, controller: "/jobs/sessions"
    end
  end

  constraints OperationsAccess do
    mount MissionControl::Jobs::Engine, at: "/admin/jobs"
  end

  namespace :webhooks do
    namespace :stripe do
      resources :events, only: :create
    end
  end

  namespace :api do
    namespace :v1 do
      resource :health, only: :show, controller: :health
      resources :direct_uploads, path: "direct-uploads", only: :create
      resources :events, only: :create
      resource :bootstrap, controller: "/api/v1/bootstrap", only: :show
      resources :locales, only: :show, param: :locale
      resources :legal_pages, path: "legal-pages", only: :show, param: :slug
      resources :email_subscriptions, path: "email-subscriptions", only: :show, param: :token do
        resource :opt_out, path: "opt-out", only: :create, controller: "/api/v1/email_subscriptions/opt_out"
      end
      resource :current_organization, controller: "/api/v1/current_organization", path: "current-organization", only: [] do
        put "", action: :update, as: :update
      end
      resources :organizations, only: :create
      resource :onboarding, controller: "/api/v1/onboarding", only: :show do
        put "", action: :update, as: :update
      end
      resources :invitations, only: :show, param: :token do
        resource :acceptance, only: :create, controller: "/api/v1/invitations/acceptance"
      end
      namespace :settings do
        resource :billing, only: :show, controller: "/api/v1/settings/billing" do
          resource :checkout_session, path: "checkout-session", only: :create, controller: "/api/v1/settings/billing/checkout_sessions"
          resource :portal_session, path: "portal-session", only: :create, controller: "/api/v1/settings/billing/portal_sessions"
        end
        resource :profile, controller: "/api/v1/settings/profile", only: [] do
          put "", action: :update, as: :update
        end
        resource :email_preferences, path: "email-preferences", only: :show do
          put "", action: :update, as: :update
        end
        resources :sessions, only: %i[index destroy]
        resource :email, controller: "/api/v1/settings/email", only: [] do
          put "", action: :update, as: :update
        end
        resources :email_confirmations, path: "email-confirmations", param: :token, only: %i[show create]
        resource :password, controller: "/api/v1/settings/password", only: [] do
          put "", action: :update, as: :update
        end
        resource :account, controller: "/api/v1/settings/account", only: %i[show destroy]
        resource :organization, controller: "/api/v1/settings/organization", only: :show do
          put "", action: :update, as: :update
        end
        resources :members, only: %i[index destroy] do
          put "", action: :update, on: :member, as: :update
        end
        resources :invitations, only: %i[index create destroy]
      end
      namespace :auth do
        namespace :google do
          resource :start, only: :show, controller: :start
          resource :callback, only: :show, controller: :callback
        end
        resources :registrations, only: :create
        resources :magic_links, path: "magic-links", param: :token, only: %i[create show] do
          resource :session, only: :create, controller: "/api/v1/auth/magic_links/sessions"
        end
        resources :sessions, only: :create
        resource :session, only: :destroy
        resource :sudo, only: :create, controller: "/api/v1/auth/sudo"
        resource :impersonation, controller: "/api/v1/auth/impersonation", only: :destroy
      end
      namespace :admin do
        resource :dashboard, controller: "/api/v1/admin/dashboard", only: :show
        resources :users, only: %i[index show] do
          put "", action: :update, on: :member, as: :update
          resource :impersonation, controller: "/api/v1/admin/users/impersonation", only: :create
        end
        resources :organizations, only: %i[index show]
        resources :translations, only: [], param: :key, constraints: { key: /[^\/]+/ } do
          put "", action: :update, on: :member, as: :update
        end
        resources :translations, only: :index
        resources :translation_fills, path: "translation-fills", only: :create
        resources :legal_documents, path: "legal-documents", only: %i[index show], param: :slug do
          resources :versions, only: :create, controller: "/api/v1/admin/legal_documents/versions", param: :number do
            resource :publication, only: :create, controller: "/api/v1/admin/legal_documents/versions/publication"
          end
        end
        resources :audit_events, path: "audit-events", only: :index
        resource :jobs_access, path: "jobs-access", only: :create, controller: "/api/v1/admin/jobs_access"
      end
    end
    match "*path", to: "errors#show", via: :all
    match "/", to: "errors#show", via: :all
  end
end
