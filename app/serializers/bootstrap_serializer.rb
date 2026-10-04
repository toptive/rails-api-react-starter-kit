class BootstrapSerializer
  include ApplicationSerializer

  typelize locale: :string, locales: "string[]", i18n_version: :string
  hash_attributes :locale, :locales, :i18n_version
  typelize auth: { nullable: true }
  one :auth, resource: AuthSerializer
  typelize app: {}
  one :app, resource: AppConfigSerializer
  typelize flags: {}
  one :flags, resource: FlagsSerializer
  typelize turnstile: {}
  one :turnstile, resource: TurnstileSerializer
end
