class Bootstrap
  def self.for_session(session, scope:)
    { auth: session && auth_for(scope), locale: I18n.locale.to_s,
      locales: I18n.available_locales.map(&:to_s), i18n_version: TranslationCatalog.version,
      app: { name: ENV.fetch("APP_NAME", "StarterKit"), tenancy: Organization.tenancy, signup_mode: User.signup_mode,
        email_available: AccountMail.available?, google_enabled: false,
        public_url: Rails.application.config.x.spa_origin, jobs_dashboard: true },
      flags: { billing: false }, turnstile: Turnstile.widget }
  end

  def self.auth_for(scope)
    session = scope.session
    { user: session.user, organization: scope.organization, membership: scope.membership, organizations: Organization.for_user(scope.user),
      superadmin: session.superadmin?, impersonator: session.impersonator_user,
      onboarding_required: Organization.onboarding_required?(scope), sudo_until: session.sudo_until, session_id: session.id }
  end
end
