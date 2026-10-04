require "net/http"
require "timeout"

class Billing::Gateway
  API_VERSION = "2025-09-30.clover"
  ENDPOINT = URI("https://api.stripe.com/v1/")

  def initialize(key)
    @key = key
  end

  def get(path) = request(:get, path, {})
  def post(path, form = {}, idempotency_key: nil, **fields) = request(:post, path, form.merge(fields), idempotency_key)

  def request(method, path, form, idempotency_key = nil)
    endpoint = Rails.env.test? && ENV["E2E_STRIPE_URL"].present? ? "#{ENV.fetch("E2E_STRIPE_URL")}/v1/" : ENDPOINT.to_s
    uri = URI.join(endpoint, path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 15
    http.write_timeout = 5
    http.max_retries = 0
    headers = { "Authorization" => "Bearer #{@key}", "Stripe-Version" => API_VERSION }
    headers["Idempotency-Key"] = idempotency_key if idempotency_key
    response = Timeout.timeout(20) do
      if method == :get
        http.get(uri.request_uri, headers)
      else
        http.post(uri.request_uri, URI.encode_www_form(flatten(form)), headers.merge("Content-Type" => "application/x-www-form-urlencoded"))
      end
    end
    body = JSON.parse(response.body)
    unless response.is_a?(Net::HTTPSuccess) && body.is_a?(Hash)
      details = body.is_a?(Hash) && body["error"].is_a?(Hash) ? body["error"].slice("type", "code", "param") : {}
      Rails.logger.warn("Stripe request refused: #{details.inspect}")
      raise ApiError.unavailable(:stripe_unavailable)
    end
    body
  rescue SocketError, Timeout::Error, IOError, SystemCallError, JSON::ParserError, OpenSSL::SSL::SSLError
    raise ApiError.unavailable(:stripe_unavailable)
  end

  private

  def flatten(value, prefix = nil)
    case value
    when Hash
      value.flat_map { |key, item| flatten(item, prefix ? "#{prefix}[#{key}]" : key.to_s) }
    when Array
      value.each_with_index.flat_map { |item, index| flatten(item, "#{prefix}[#{index}]") }
    else
      [ [ prefix, value.to_s ] ]
    end
  end
end
