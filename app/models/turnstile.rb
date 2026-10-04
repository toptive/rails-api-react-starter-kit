require "net/http"
require "timeout"

class Turnstile
  VERIFY_URL = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")

  def self.required? = ENV["TURNSTILE_REQUIRED"] == "true"
  def self.widget = { required: required?, site_key: required? ? ENV["TURNSTILE_SITE_KEY"].presence : nil }

  def self.verify!(token, action:, request:)
    return unless required?
    raise refusal unless accepted?(token, action, request.remote_ip)
  end

  def self.accepted?(token, action, ip)
    return false unless token.is_a?(String) && token.bytesize.between?(1, 2048)
    return false if ENV["TURNSTILE_SECRET_KEY"].blank? || ENV["TURNSTILE_HOSTNAME"].blank?

    response = Timeout.timeout(5) do
      http = Net::HTTP.new(VERIFY_URL.host, VERIFY_URL.port)
      http.use_ssl = true
      http.open_timeout = 2
      http.read_timeout = 3
      http.write_timeout = 2
      http.max_retries = 0
      http.post(VERIFY_URL.request_uri, URI.encode_www_form(secret: ENV.fetch("TURNSTILE_SECRET_KEY"),
        response: token, remoteip: ip), "Content-Type" => "application/x-www-form-urlencoded")
    end
    body = JSON.parse(response.body)
    response.is_a?(Net::HTTPSuccess) && body["success"] == true &&
      body["hostname"] == ENV.fetch("TURNSTILE_HOSTNAME") && body["action"] == action
  rescue Timeout::Error, IOError, SystemCallError, JSON::ParserError, OpenSSL::SSL::SSLError
    false
  end
  private_class_method :accepted?

  def self.refusal
    ApiError.unprocessable(:turnstile_failed, User.validation_details(:turnstile_token, "validation.turnstile_required"))
  end
  private_class_method :refusal
end
