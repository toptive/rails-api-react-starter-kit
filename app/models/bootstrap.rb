class Bootstrap
  def self.for_session(session)
    { auth: session && auth_for(session), locale: I18n.locale.to_s,
      locales: I18n.available_locales.map(&:to_s), i18n_version: TranslationCatalog.version,
      app: { name: ENV.fetch("APP_NAME", "StarterKit"), tenancy: "multi", signup_mode: User.signup_mode,
        email_available: AccountMail.available?, google_enabled: false,
        public_url: ENV.fetch("SPA_ORIGIN", ENV.fetch("PUBLIC_URL", "http://localhost:5173")) },
      flags: { billing: false }, turnstile: Turnstile.widget }
  end

  def self.auth_for(session)
    { user: session.user, organization: nil, membership: nil, organizations: [],
      superadmin: session.superadmin?, impersonator: session.impersonator_user,
      onboarding_required: false, sudo_until: session.sudo_until, session_id: session.id }
  end
end
