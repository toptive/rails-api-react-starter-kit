if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV.fetch("SENTRY_DSN")
    config.environment = ENV.fetch("SENTRY_ENV", Rails.env)
    config.release = ENV["KAMAL_VERSION"]
    config.send_default_pii = false
    config.traces_sample_rate = 0.0
    config.before_send = ->(event, hint) { Monitoring.scrub(event, hint) }
  end
end
