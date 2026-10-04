require "test_helper"
require_relative "../support/auth_requests"

class TurnstileTest < ActionDispatch::IntegrationTest
  include AuthRequests

  setup do
    @saved_turnstile_env = ENV.to_h.slice("TURNSTILE_SECRET_KEY", "TURNSTILE_HOSTNAME", "TURNSTILE_SITE_KEY")
    ENV["TURNSTILE_REQUIRED"] = "true"
    ENV["TURNSTILE_SECRET_KEY"] = "test-secret"
    ENV["TURNSTILE_HOSTNAME"] = "app.example.com"
    ENV["TURNSTILE_SITE_KEY"] = "public-test-site-key"
  end

  teardown do
    %w[TURNSTILE_SECRET_KEY TURNSTILE_HOSTNAME TURNSTILE_SITE_KEY].each { |key| ENV[key] = @saved_turnstile_env[key] }
  end

  test "missing challenges refuse both public writes without creating users or tokens" do
    [ "/api/v1/auth/registrations", "/api/v1/auth/magic-links" ].each do |path|
      assert_no_difference [ "User.count", "UserToken.count", "AuditEvent.count" ] do
        post path, params: { name: "Ana", email: "ana@example.com", termsAccepted: true }, as: :json
      end
      assert_error :unprocessable_entity, "turnstile_failed"
      assert_equal "validation.turnstile_required", response.parsed_body.dig("error", "details", "turnstileToken", 0, "key")
    end
    get "/api/v1/bootstrap"
    assert_equal({ "required" => true, "siteKey" => "public-test-site-key" }, data.fetch("turnstile"))
    refute_includes response.body, "test-secret"
  end

  test "siteverify validates success hostname and registration action before creating an account" do
    with_siteverify({ success: true, hostname: "app.example.com", action: "registration" }) do |http|
      post "/api/v1/auth/registrations", params: { name: "Ana", email: "ana@example.com",
        termsAccepted: true, turnstileToken: "challenge" }, as: :json
      assert_response :accepted
      assert_equal 0, http.max_retries
      assert_equal 2, http.open_timeout
      assert_equal 3, http.read_timeout
    end
  end

  test "siteverify refusal wrong host wrong action invalid JSON and timeout fail closed" do
    bodies = [ { success: false }, { success: true, hostname: "other.example.com", action: "registration" },
      { success: true, hostname: "app.example.com", action: "magic_link" }, "invalid-json", :timeout ]
    bodies.each do |body|
      with_siteverify(body) do
        assert_no_difference [ "User.count", "UserToken.count", "AuditEvent.count" ] do
          post "/api/v1/auth/registrations", params: { name: "Ana", email: "ana@example.com",
            termsAccepted: true, turnstileToken: "challenge" }, as: :json
        end
        assert_error :unprocessable_entity, "turnstile_failed"
      end
    end
  end

  test "magic link siteverify uses the magic link action" do
    user = create_user
    with_siteverify({ success: true, hostname: "app.example.com", action: "magic_link" }) do
      post "/api/v1/auth/magic-links", params: { email: user.email, turnstileToken: "challenge" }, as: :json
      assert_response :accepted
    end
  end

  private

  def with_siteverify(body)
    http = Net::HTTP.new("challenges.cloudflare.com", 443)
    calls = 0
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) { body.is_a?(Hash) ? JSON.generate(body) : body }
    handler = lambda do |path, payload, _headers|
      calls += 1
      assert_equal "/turnstile/v0/siteverify", path
      submitted = URI.decode_www_form(payload).to_h
      assert_equal "test-secret", submitted.fetch("secret")
      assert_equal "challenge", submitted.fetch("response")
      assert_equal "127.0.0.1", submitted.fetch("remoteip")
      raise Net::ReadTimeout if body == :timeout

      response
    end
    Net::HTTP.stub(:new, http) do
      http.stub(:post, handler) { yield http }
    end
    assert_equal 1, calls
  end
end
