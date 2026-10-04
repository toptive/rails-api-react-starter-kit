require "test_helper"
require_relative "../support/admin_requests"

class AdminTranslationFillsTest < ActionDispatch::IntegrationTest
  include AdminRequests

  setup do
    @saved_ai_key = ENV["OPENROUTER_API_KEY"]
    ENV["OPENROUTER_API_KEY"] = "test-key"
    Translation.create!(key: "custom.fill", locale: "en", value: "Hello {{name}}", edited: true)
    Translation.create!(key: "custom.fill", locale: "es", value: "", edited: true)
  end

  teardown { ENV["OPENROUTER_API_KEY"] = @saved_ai_key }

  test "fills missing cells through OpenRouter marks them edited and publishes a new catalogue" do
    get "/api/v1/locales/es"
    version = response.parsed_body.dig("meta", "version")
    with_provider({ "custom.fill" => "Hola {{name}}", "unknown.key" => "Ignore" }) do |http|
      post "/api/v1/admin/translation-fills", params: { locale: "es" }, headers: admin_headers, as: :json
      assert_response :created
      assert_equal({ "count" => 1 }, data)
      assert_equal 0, http.max_retries
    end
    cell = Translation.find_by!(key: "custom.fill", locale: "es")
    assert cell.edited?
    assert_equal "Hola {{name}}", cell.value
    refute Translation.exists?(key: "unknown.key")
    assert_equal 1, AuditEvent.where(action: "translation.updated", subject_id: cell.id).count
    assert_equal({ "locale" => "es", "count" => 1 }, AuditEvent.find_by!(action: "translation.filled").metadata)
    Translation.sync!
    get "/api/v1/locales/es"
    assert_equal "Hola {{name}}", data.fetch("custom.fill")
    refute_equal version, response.parsed_body.dig("meta", "version")
    Net::HTTP.stub(:new, ->(*) { flunk "No provider call when nothing is missing" }) do
      post "/api/v1/admin/translation-fills", params: { locale: "es" }, headers: admin_headers, as: :json
      assert_response :created
      assert_equal({ "count" => 0 }, data)
    end
  end

  test "missing API key is ai_not_configured before any writes" do
    ENV.delete("OPENROUTER_API_KEY")
    assert_no_difference [ "Translation.count", "AuditEvent.count" ] do
      post "/api/v1/admin/translation-fills", params: { locale: "es" }, headers: admin_headers, as: :json
    end
    assert_error :service_unavailable, "ai_not_configured"
  end

  test "default or unsupported fill locales are refused and locale is a required string" do
    [ "en", "fr", "" ].each do |locale|
      post "/api/v1/admin/translation-fills", params: { locale: locale }, headers: admin_headers, as: :json
      assert_admin_field "locale", "validation.inclusion"
    end
    [ {}, { locale: 2 }, { locale: nil } ].each do |attributes|
      post "/api/v1/admin/translation-fills", params: attributes, headers: admin_headers, as: :json
      assert_error :bad_request, "bad_request"
    end
  end

  test "provider errors malformed replies missing translations and altered placeholders fail atomically" do
    [ :timeout, :http_error, :malformed, [], {}, { "custom.fill" => 42 },
      { "custom.fill" => "Hola" }, { "custom.fill" => "" }, { "custom.fill" => "a" * 20_001 } ].each do |reply|
      with_provider(reply) do
        assert_no_difference [ "Translation.count", "AuditEvent.count" ] do
          post "/api/v1/admin/translation-fills", params: { locale: "es" }, headers: admin_headers, as: :json
        end
        assert_error :service_unavailable, "ai_unavailable"
        assert_equal "", Translation.find_by!(key: "custom.fill", locale: "es").value
      end
    end
  end

  test "a manual edit during the provider request wins over the fill" do
    with_provider({ "custom.fill" => "Hola {{name}}" }, during_request: -> {
      Translation.find_by!(key: "custom.fill", locale: "es").update!(value: "Manual {{name}}", edited: true)
    }) do
      post "/api/v1/admin/translation-fills", params: { locale: "es" }, headers: admin_headers, as: :json
      assert_response :created
      assert_equal({ "count" => 0 }, data)
    end
    assert_equal "Manual {{name}}", Translation.find_by!(key: "custom.fill", locale: "es").value
  end

  private

  def with_provider(reply, during_request: nil)
    http = Net::HTTP.new("openrouter.ai", 443)
    handler = lambda do |path, payload, headers|
      assert_equal "/api/v1/chat/completions", path
      assert_equal "Bearer test-key", headers.fetch("Authorization")
      body = JSON.parse(payload)
      assert_equal "json_object", body.dig("response_format", "type")
      assert_equal({ "custom.fill" => "Hello {{name}}" }, JSON.parse(body.fetch("messages").last.fetch("content")))
      during_request&.call
      raise Net::ReadTimeout if reply == :timeout

      response = reply == :http_error ? Net::HTTPServiceUnavailable.new("1.1", "503", "Unavailable") : Net::HTTPOK.new("1.1", "200", "OK")
      response.define_singleton_method(:body) do
        reply == :malformed ? "not-json" : JSON.generate(choices: [ { message: { content: JSON.generate(reply) } } ])
      end
      response
    end
    Net::HTTP.stub(:new, http) { http.stub(:post, handler) { yield http } }
  end
end
