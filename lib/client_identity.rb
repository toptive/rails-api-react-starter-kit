class ClientIdentity
  def initialize(app)
    @app = app
  end

  def call(env)
    unless trusted_peer?(env["REMOTE_ADDR"])
      %w[HTTP_X_FORWARDED_FOR HTTP_CLIENT_IP HTTP_FORWARDED HTTP_X_REAL_IP].each { |header| env.delete(header) }
    end
    # Cloudflare's header is not authoritative outside its verified proxy network.
    env.delete("HTTP_CF_CONNECTING_IP")
    @app.call(env)
  end

  private

  def trusted_peer?(address)
    ip = IPAddr.new(address.to_s)
    Rails.application.config.action_dispatch.trusted_proxies.any? { |range| range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    false
  end
end
