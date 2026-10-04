require "net/http"
require "timeout"

module Ai
  ENDPOINT = URI("https://openrouter.ai/api/v1/chat/completions")

  def self.require_configured!(key = "OPENROUTER_API_KEY")
    raise ApiError.unavailable(:ai_not_configured) if ENV[key].blank?
  end

  def self.chat(messages, **options)
    require_configured!
    payload = { model: ENV.fetch("OPENROUTER_MODEL", "openai/gpt-4o-mini"), messages: messages }.merge(options)
    body = request(ENDPOINT, payload, "Authorization" => "Bearer #{ENV.fetch('OPENROUTER_API_KEY')}")
    content = body.dig("choices", 0, "message", "content")
    raise ApiError.unavailable(:ai_unavailable) unless content.is_a?(String)

    content
  rescue TypeError
    raise ApiError.unavailable(:ai_unavailable)
  end

  def self.translate_strings(strings, from:, to:)
    content = chat([
      { role: "system", content: "Translate UI text from #{from} to #{to}. Preserve JSON keys and {{placeholders}} exactly. Return only a JSON object." },
      { role: "user", content: JSON.generate(strings) }
    ], temperature: 0.2, response_format: { type: "json_object" })
    result = JSON.parse(content)
    valid = result.is_a?(Hash) && strings.keys.all? do |key|
      value = result[key]
      value.is_a?(String) && value.present? && value.length <= 20_000 &&
        value.scan(/\{\{\w+\}\}/).sort == strings[key].scan(/\{\{\w+\}\}/).sort
    end
    raise ApiError.unavailable(:ai_unavailable) unless valid

    result.slice(*strings.keys)
  rescue JSON::ParserError, TypeError
    raise ApiError.unavailable(:ai_unavailable)
  end

  def self.fal(model, input)
    require_configured!("FAL_KEY")
    raise ArgumentError unless model.is_a?(String) && model.match?(%r{\A[a-zA-Z0-9_-]+(?:/[a-zA-Z0-9_-]+)+\z})

    request(URI("https://fal.run/#{model}"), input, "Authorization" => "Key #{ENV.fetch('FAL_KEY')}")
  end

  def self.gemini(prompt)
    require_configured!("GOOGLE_API_KEY")
    model = ENV.fetch("GEMINI_MODEL", "gemini-2.5-flash")
    raise ArgumentError unless model.match?(/\A[a-zA-Z0-9_.-]+\z/)

    body = request(URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent"),
      { contents: [ { parts: [ { text: prompt } ] } ] }, "x-goog-api-key" => ENV.fetch("GOOGLE_API_KEY"))
    content = body.dig("candidates", 0, "content", "parts", 0, "text")
    raise ApiError.unavailable(:ai_unavailable) unless content.is_a?(String)

    content
  rescue TypeError
    raise ApiError.unavailable(:ai_unavailable)
  end

  def self.request(uri, payload, headers)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 20
    http.write_timeout = 5
    http.max_retries = 0
    response = Timeout.timeout(25) { http.post(uri.request_uri, JSON.generate(payload), headers.merge("Content-Type" => "application/json")) }
    raise ApiError.unavailable(:ai_unavailable) unless response.is_a?(Net::HTTPSuccess)

    body = JSON.parse(response.body)
    raise ApiError.unavailable(:ai_unavailable) unless body.is_a?(Hash)

    body
  rescue SocketError, Timeout::Error, IOError, SystemCallError, JSON::ParserError, TypeError, OpenSSL::SSL::SSLError
    raise ApiError.unavailable(:ai_unavailable)
  end
  private_class_method :request
end
