require "test_helper"
require_relative "../support/auth_requests"

class AnalyticsTest < ActionDispatch::IntegrationTest
  include AuthRequests

  setup do
    @analytics_env = ENV.to_h.slice("POSTHOG_API_KEY", "POSTHOG_HOST")
    ENV.delete("POSTHOG_API_KEY")
    ENV.delete("POSTHOG_HOST")
  end
  teardown { %w[POSTHOG_API_KEY POSTHOG_HOST].each { |name| ENV[name] = @analytics_env[name] } }

  test "public events acknowledge allowed names and keep only safe catalogue properties" do
    events = []
    capture = ->(event) { events << event.payload }
    ActiveSupport::Notifications.subscribed(capture, "page_viewed") do
      post "/api/v1/events", params: { name: "page_viewed", properties: { page: "home.show", email: "private@example.com", url: "https://example.com" } }, as: :json
    end
    assert_response :accepted
    assert_equal({ "accepted" => true }, data)
    assert_equal [ { page: "home.show", user_id: nil, organization_id: nil } ], events
    ActiveSupport::Notifications.subscribed(capture, "page_viewed") do
      post "/api/v1/events", params: { name: "page_viewed", properties: { page: "private@example.com" } }, as: :json
    end
    assert_equal({ user_id: nil, organization_id: nil }, events.last)
    post "/api/v1/events", params: { name: "cta_clicked", properties: "not an object" }, as: :json
    assert_response :accepted
  end

  test "unknown client and server event names are ignored and missing or invalid names are bad request" do
    Analytics.stub(:track, ->(*) { flunk "Unknown client event must be ignored" }) do
      [ "unknown", "subscription_started", "user_registered" ].each do |name|
        post "/api/v1/events", params: { name: name }, as: :json
        assert_response :accepted
      end
    end
    [ {}, { name: nil }, { name: 1 }, { name: "" } ].each do |params|
      post "/api/v1/events", params: params, as: :json
      assert_error :bad_request, "bad_request"
    end
  end

  test "analytics without a provider key never makes a network call" do
    Net::HTTP.stub(:new, ->(*) { flunk "No analytics network call without a key" }) do
      post "/api/v1/events", params: { name: "page_viewed", properties: { page: "home" } }, as: :json
      assert_response :accepted
    end
  end

  test "PostHog delivery is scheduled outside the request and disables anonymous person profiles and geoip" do
    ENV["POSTHOG_API_KEY"] = "test-posthog"
    ENV["POSTHOG_HOST"] = "https://analytics.example"
    tasks = []
    Analytics::EXECUTOR.stub(:post, ->(&block) { tasks << block }) do
      post "/api/v1/events", params: { name: "cta_clicked", properties: { cta: "start", page: "home", email: "private@example.com" } }, as: :json
      assert_response :accepted
    end
    assert_equal 1, tasks.length
    http = Net::HTTP.new("analytics.example", 443)
    Net::HTTP.stub(:new, http) do
      http.stub(:post, ->(path, payload, headers) {
        assert_equal "/capture/", path
        assert_equal "application/json", headers.fetch("Content-Type")
        body = JSON.parse(payload)
        assert_equal "test-posthog", body.fetch("api_key")
        assert_equal "cta_clicked", body.fetch("event")
        assert_equal false, body.dig("properties", "$process_person_profile")
        assert_equal true, body.dig("properties", "$geoip_disable")
        assert_match(/[0-9a-f-]{36}/, body.dig("properties", "distinct_id"))
        refute_includes payload, "private@example.com"
        assert_equal 0, http.max_retries
        Net::HTTPOK.new("1.1", "200", "OK")
      }) { tasks.first.call }
    end
  end

  test "authenticated events use the user id and discard unsafe identifiers" do
    user = create_user
    token = sign_in(user)
    events = []
    ActiveSupport::Notifications.subscribed(->(event) { events << event.payload }, "cta_clicked") do
      post "/api/v1/events", params: { name: "cta_clicked", properties: { cta: "a" * 41, page: "https://example.com" } },
        headers: bearer(token), as: :json
    end
    assert_response :accepted
    assert_equal user.id, events.first.fetch(:user_id)
    refute events.first.key?(:cta)
    refute events.first.key?(:page)
  end

  test "public events are limited to 120 per minute" do
    120.times { post "/api/v1/events", params: { name: "unknown" }, as: :json }
    assert_response :accepted
    post "/api/v1/events", params: { name: "unknown" }, as: :json
    assert_error :too_many_requests, "rate_limited"
    assert_equal "60", response.headers["Retry-After"]
  end

  test "bootstrap exposes only public flags and a test override is scoped to its block" do
    Flags.with(:billing, false) do
      get "/api/v1/bootstrap"
      assert_equal({ "billing" => false }, data.fetch("flags"))
    end
    Flags.with(:billing, true) do
      get "/api/v1/bootstrap"
      assert_equal({ "billing" => true }, data.fetch("flags"))
      assert_equal Billing.public_url, data.dig("app", "publicUrl")
    end
    assert_raises(KeyError) { Flags.enabled?(:unknown) }
  end
end
