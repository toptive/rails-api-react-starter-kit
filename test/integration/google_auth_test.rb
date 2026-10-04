require "test_helper"
require_relative "../support/auth_requests"

class GoogleAuthTest < ActionDispatch::IntegrationTest
  include AuthRequests

  setup do
    @google_environment = ENV.to_h.slice("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "SIGNUP_MODE")
    ENV["GOOGLE_CLIENT_ID"] = "browser-fixture-client"
    ENV["GOOGLE_CLIENT_SECRET"] = "browser-fixture-secret"
  end

  teardown do
    %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET SIGNUP_MODE].each { |key| ENV.delete(key) }
    @google_environment.each { |key, value| ENV[key] = value }
  end

  test "Google navigation is disabled without configuration" do
    ENV.delete("GOOGLE_CLIENT_SECRET")
    get "/api/v1/auth/google/start"
    assert_error :not_found, "not_found"
    get "/api/v1/bootstrap"
    assert_equal false, data.dig("app", "googleEnabled")
  end

  test "signed state expires and external return paths never become redirect destinations" do
    get "/api/v1/auth/google/start", params: { returnTo: "//evil.example", client: "web" }
    assert_response :found
    uri = URI(response.location)
    assert_equal "accounts.google.com", uri.host
    query = URI.decode_www_form(uri.query).to_h
    assert_equal "openid email profile", query.fetch("scope")
    assert_match(/\A[a-zA-Z0-9_-]+--[a-f0-9]{64}\z/, query.fetch("state"))
    with_google_profile do
      get "/api/v1/auth/google/callback", params: { state: query.fetch("state"), code: "fixture-code" }
    end
    assert_response :found
    refute URI.decode_www_form(URI(response.location).fragment).to_h.key?("returnTo")
    travel 11.minutes do
      get "/api/v1/auth/google/callback", params: { state: query.fetch("state"), code: "expired" }
      assert_response :found
      assert_equal "state_invalid", URI.decode_www_form(URI(response.location).fragment).to_h.fetch("error")
    end
  end

  test "verified Google identity links an existing account and creates a real bearer without cookies" do
    user = create_user
    get "/api/v1/auth/google/start", params: { returnTo: "/settings/profile/edit" }
    state = URI.decode_www_form(URI(response.location).query).to_h.fetch("state")
    with_google_profile(email: user.email) do
      assert_no_difference "User.count" do
        get "/api/v1/auth/google/callback", params: { state: state, code: "fixture-code" }
      end
    end
    assert_response :found
    handoff = URI(response.location)
    assert_equal URI(Rails.application.config.x.spa_origin).host, handoff.host
    assert_equal "/auth/callback", handoff.path
    fragment = URI.decode_www_form(handoff.fragment).to_h
    assert_equal "/settings/profile/edit", fragment.fetch("returnTo")
    assert_equal "0", fragment.fetch("new")
    assert Time.iso8601(fragment.fetch("expiresAt")) > Time.current
    assert_equal "fixture-google-uid", user.reload.google_uid
    get "/api/v1/bootstrap", headers: bearer(fragment.fetch("token"))
    assert_equal user.id, data.dig("auth", "user", "id")
    assert_nil response.headers["Set-Cookie"]
  end

  test "verified signup creates a confirmed localized account and hands off to the native app" do
    ENV["SIGNUP_MODE"] = "open"
    get "/api/v1/auth/google/start", params: { client: "native", locale: "es" }
    state = URI.decode_www_form(URI(response.location).query).to_h.fetch("state")
    with_google_profile do
      assert_difference "User.count", 1 do
        get "/api/v1/auth/google/callback", params: { state: state, code: "fixture-code" }
      end
    end
    assert_response :found
    handoff = URI(response.location)
    assert_equal ENV.fetch("NATIVE_SCHEME", "starterkit"), handoff.scheme
    assert_equal "auth", handoff.host
    assert_equal "/callback", handoff.path
    fragment = URI.decode_www_form(handoff.fragment).to_h
    assert_equal "1", fragment.fetch("new")
    assert Time.iso8601(fragment.fetch("expiresAt")) > Time.current
    user = User.find_by!(email: "google-new@example.com")
    assert user.confirmed_at
    assert_equal "es", user.locale
    assert AuditEvent.exists?(action: "user.registered", actor_id: user.id)
    get "/api/v1/bootstrap", headers: bearer(fragment.fetch("token"))
    assert_equal user.id, data.dig("auth", "user", "id")
  end

  test "unverified identities and restricted signup cannot create accounts or sessions" do
    [ [ false, "open", "email_not_verified" ], [ true, "closed", "signup_closed" ],
      [ true, "invite", "invitation_required" ] ].each do |verified, signup, error|
      ENV["SIGNUP_MODE"] = signup
      get "/api/v1/auth/google/start"
      state = URI.decode_www_form(URI(response.location).query).to_h.fetch("state")
      with_google_profile(verified: verified) do
        assert_no_difference [ "User.count", "Session.count" ] do
          get "/api/v1/auth/google/callback", params: { state: state, code: "fixture-code" }
        end
      end
      assert_response :found
      assert_equal error, URI.decode_www_form(URI(response.location).fragment).to_h.fetch("error")
    end
  end

  { "start" => 10, "callback" => 20 }.each do |resource, limit|
    test "Google #{resource} allows #{limit} requests per minute per IP" do
      path = "/api/v1/auth/google/#{resource}"
      headers = { "REMOTE_ADDR" => "203.0.113.1" }
      limit.times do
        get path, headers: headers
        assert_response :found
      end
      get path, headers: headers
      assert_error :too_many_requests, "rate_limited"
      assert_equal "60", response.headers["Retry-After"]
      assert_equal 60, response.parsed_body.dig("error", "details", "retryAfter")
      get path, headers: { "REMOTE_ADDR" => "203.0.113.2" }
      assert_response :found
      travel 61.seconds do
        get path, headers: headers
        assert_response :found
      end
    end
  end

  private

  def with_google_profile(email: "google-new@example.com", verified: true)
    transport = Object.new
    transport.define_singleton_method(:request) do |request|
      payload = request.is_a?(Net::HTTP::Post) ? { access_token: "fixture-access-token" } :
        { email: email, name: "Google Tester", sub: "fixture-google-uid", email_verified: verified }
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.define_singleton_method(:body) { JSON.generate(payload) }
      response
    end
    Net::HTTP.stub(:start, ->(*, **, &block) { block.call(transport) }) { yield }
  end
end
