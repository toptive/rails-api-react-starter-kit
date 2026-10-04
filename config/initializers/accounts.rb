raise ArgumentError, "SIGNUP_MODE must be open, invite or closed" unless %w[open invite closed].include?(ENV.fetch("SIGNUP_MODE", "open"))

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
