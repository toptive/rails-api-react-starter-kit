require "net/http"
require "timeout"

class Analytics
  CATALOGUE = {
    "signup_started" => { via: %w[email google] },
    "user_registered" => { via: %w[email google] },
    "signup_confirmed" => {},
    "onboarding_completed" => { skipped: :boolean },
    "checkout_started" => { plan: 40, interval: %w[month year], mode: %w[test live] },
    "subscription_started" => { plan: 40, interval: %w[month year], mode: %w[test live] },
    "subscription_canceled" => { plan: 40, mode: %w[test live] },
    "user_signed_in" => { method: %w[magic_link password google] },
    "organization_created" => {},
    "invitation_sent" => { role: %w[owner admin member] },
    "invitation_accepted" => {},
    "page_viewed" => { page: 80 },
    "cta_clicked" => { cta: 40, page: 80 }
  }.freeze
  CLIENT = %w[page_viewed cta_clicked].freeze
  EXECUTOR = Concurrent::ThreadPoolExecutor.new(min_threads: 0, max_threads: 8, max_queue: 100, fallback_policy: :discard)

  def self.receive(attributes, session)
    name = attributes[:name]
    raise ApiError.bad_request unless name.is_a?(String) && name.present?

    track(name, nil, attributes[:properties], user_id: session&.user_id) if CLIENT.include?(name)
    { accepted: true }
  end

  def self.track(name, scope = nil, properties = {}, user_id: nil, organization_id: nil, **attributes)
    rules = CATALOGUE[name]
    unless rules
      raise ArgumentError, "Unknown analytics event: #{name}" unless Rails.env.production?

      return
    end
    properties = properties.respond_to?(:to_unsafe_h) ? properties.to_unsafe_h : properties
    properties = properties.is_a?(Hash) ? properties.symbolize_keys.merge(attributes) : attributes
    safe = rules.filter_map do |key, rule|
      value = properties[key]
      [ key, value ] if valid?(value, rule)
    end.to_h
    actor_id = scope&.user&.id || user_id
    ActiveSupport::Notifications.instrument(name, **safe, user_id: actor_id, organization_id: scope&.organization&.id || organization_id)
    return if ENV["POSTHOG_API_KEY"].blank?

    payload = { api_key: ENV.fetch("POSTHOG_API_KEY"), event: name,
      properties: safe.merge(distinct_id: actor_id || SecureRandom.uuid, "$geoip_disable" => true, "$process_person_profile" => !actor_id.nil?) }
    host = ENV["POSTHOG_HOST"]
    return if host.blank?

    EXECUTOR.post { deliver(host, payload) }
  end

  def self.valid?(value, rule)
    case rule
    when Array then rule.include?(value)
    when Integer then value.is_a?(String) && value.bytesize.between?(1, rule) && value.match?(/\A[a-zA-Z0-9_.-]+\z/)
    when :boolean then [ true, false ].include?(value)
    else false
    end
  end
  private_class_method :valid?

  def self.deliver(host, payload)
    uri = URI.join(host.delete_suffix("/") + "/", "capture/")
    return unless uri.scheme == "https"

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = http.read_timeout = http.write_timeout = 2
    http.max_retries = 0
    Timeout.timeout(3) { http.post(uri.request_uri, JSON.generate(payload), "Content-Type" => "application/json") }
  rescue SocketError, Timeout::Error, IOError, SystemCallError, OpenSSL::SSL::SSLError, URI::InvalidURIError
    nil
  end
  private_class_method :deliver
end
