raise ArgumentError, "SIGNUP_MODE must be open, invite or closed" unless %w[open invite closed].include?(ENV.fetch("SIGNUP_MODE", "open"))
raise ArgumentError, "SPA_ORIGIN is required in production" if Rails.env.production? && ENV["SPA_ORIGIN"].blank?

Rails.application.config.x.spa_origin = ENV["SPA_ORIGIN"].presence || ENV["PUBLIC_URL"].presence || "http://localhost:5173"
Rails.application.config.x.api_origin = ENV["API_ORIGIN"].presence || "http://localhost:3000"
raise ArgumentError, "API_ORIGIN is required in production" if Rails.env.production? && ENV["API_ORIGIN"].blank?
Rails.application.config.x.tenancy = ENV.fetch("TENANCY", "multi")
raise ArgumentError, "TENANCY must be multi or single" unless %w[multi single].include?(Rails.application.config.x.tenancy)

# Resolve proxy headers only when the peer belongs to an explicitly trusted proxy.
Rails.application.config.action_dispatch.trusted_proxies = ENV.fetch("TRUSTED_PROXY_CIDRS", "").split(",").filter_map do |cidr|
  IPAddr.new(cidr.strip) if cidr.strip.present?
end

# Mail delivery logs must not include access links or message bodies.
ActionMailer::Base.logger = ActiveSupport::Logger.new($stdout, level: Logger::INFO)

Rails.application.config.active_job.log_arguments = false

Rails.application.config.middleware.insert_before ActionDispatch::RemoteIp, ClientIdentity
Rails.application.config.middleware.insert_before ActionDispatch::RemoteIp, OperationsBrowserSession
Rails.application.config.to_prepare { Session.redact_logs! }
