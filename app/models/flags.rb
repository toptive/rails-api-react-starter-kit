class Flags
  DEFINITIONS = {
    billing: { env: "BILLING_ENABLED", default: false, public: true },
    billing_renewal_notices: { env: "BILLING_RENEWAL_NOTICES", default: false },
    site_indexing: { env: "SITE_INDEXING", default: !Rails.env.production? },
    turnstile: { env: "TURNSTILE_REQUIRED", default: false }
  }.freeze

  def self.enabled?(name)
    definition = DEFINITIONS.fetch(name)
    overrides = Thread.current[:platform_flags] || {}
    return overrides.fetch(name) if Rails.env.test? && overrides.key?(name)

    value = ENV[definition.fetch(:env)]
    return %w[true 1].include?(value) if value.present?

    (Rails.application.config.x.feature_flags || {}).fetch(name, definition.fetch(:default))
  end

  def self.public_flags = DEFINITIONS.filter_map { |name, definition| [ name, enabled?(name) ] if definition[:public] }.to_h

  def self.with(name, value)
    previous = Thread.current[:platform_flags]
    raise ArgumentError unless Rails.env.test? && DEFINITIONS.key?(name) && [ true, false ].include?(value)
    Thread.current[:platform_flags] = (previous || {}).merge(name => value)
    yield
  ensure
    Thread.current[:platform_flags] = previous
  end

  def self.check!
    problems = []
    problems.concat(Billing.readiness) if enabled?(:billing)
    problems.concat(Turnstile.readiness) if enabled?(:turnstile)
    problems << "POSTHOG_HOST is required with POSTHOG_API_KEY" if ENV["POSTHOG_API_KEY"].present? && ENV["POSTHOG_HOST"].blank?
    raise ArgumentError, problems.join("; ") if problems.any?
  end
end
