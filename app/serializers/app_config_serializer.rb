class AppConfigSerializer
  include ApplicationSerializer

  typelize name: :string, tenancy: '"multi" | "single"', signup_mode: '"open" | "invite" | "closed"',
    email_available: :boolean, google_enabled: :boolean, public_url: :string, jobs_dashboard: :boolean
  hash_attributes :name, :tenancy, :signup_mode, :email_available, :google_enabled, :public_url, :jobs_dashboard
end
