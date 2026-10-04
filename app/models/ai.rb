require "net/http"
require "timeout"

module Ai
  ENDPOINT = URI("https://openrouter.ai/api/v1/chat/completions")

  def self.require_configured!
    raise ApiError.unavailable(:ai_not_configured) if ENV["OPENROUTER_API_KEY"].blank?
  end

  def self.translate_strings(strings, from:, to:)
    require_configured!
    http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 60
    http.write_timeout = 5
    http.max_retries = 0
    payload = { model: ENV.fetch("OPENROUTER_MODEL", "openai/gpt-4o-mini"), temperature: 0.2,
      response_format: { type: "json_object" }, messages: [
        { role: "system", content: "Translate UI text from #{from} to #{to}. Preserve JSON keys and {{placeholders}} exactly. Return only a JSON object." },
        { role: "user", content: JSON.generate(strings) }
      ] }
    response = Timeout.timeout(70) do
      http.post(ENDPOINT.request_uri, JSON.generate(payload),
        "Authorization" => "Bearer #{ENV.fetch('OPENROUTER_API_KEY')}", "Content-Type" => "application/json")
    end
    raise ApiError.unavailable(:ai_unavailable) unless response.is_a?(Net::HTTPSuccess)

    body = JSON.parse(response.body)
    content = body.is_a?(Hash) && body.dig("choices", 0, "message", "content")
    result = content.is_a?(String) && JSON.parse(content)
    valid = result.is_a?(Hash) && strings.keys.all? do |key|
      value = result[key]
      value.is_a?(String) && value.present? && value.length <= 20_000 &&
        value.scan(/\{\{\w+\}\}/).sort == strings[key].scan(/\{\{\w+\}\}/).sort
    end
    raise ApiError.unavailable(:ai_unavailable) unless valid

    result.slice(*strings.keys)
  rescue Timeout::Error, IOError, SystemCallError, JSON::ParserError, TypeError, OpenSSL::SSL::SSLError
    raise ApiError.unavailable(:ai_unavailable)
  end
end
