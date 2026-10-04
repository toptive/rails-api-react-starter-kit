require "test_helper"
require_relative "../support/auth_requests"

class AuthRateLimitsTest < ActionDispatch::IntegrationTest
  include AuthRequests

  { "/api/v1/auth/registrations" => 10, "/api/v1/auth/magic-links" => 5,
    "/api/v1/auth/magic-links/invalid/session" => 10, "/api/v1/auth/sessions" => 10,
    "/api/v1/auth/sudo" => 5 }.each do |path, limit|
    test "#{path} limits work to #{limit} requests per minute per IP" do
      token = sign_in(create_user)
      Api::V1::BaseController::RATE_LIMIT_STORE.clear
      headers = bearer(token).merge("REMOTE_ADDR" => "203.0.113.1")
      limit.times do
        post path, params: { email: "missing@example.com", password: "wrong" }, headers: headers, as: :json
        refute_equal 429, response.status
      end
      post path, params: { email: "missing@example.com", password: "wrong" }, headers: headers, as: :json
      assert_error :too_many_requests, "rate_limited"
      assert_equal "60", response.headers["Retry-After"]
      assert_equal 60, response.parsed_body.dig("error", "details", "retryAfter")
      post path, params: { email: "missing@example.com" }, headers: bearer(token).merge("REMOTE_ADDR" => "203.0.113.2"), as: :json
      refute_equal 429, response.status
      travel 61.seconds do
        post path, params: { email: "missing@example.com" }, headers: headers, as: :json
        refute_equal 429, response.status
      end
    end
  end

  test "untrusted forwarded headers cannot bypass the limit" do
    5.times do |index|
      post "/api/v1/auth/magic-links", params: { email: "missing@example.com" },
        headers: { "X-Forwarded-For" => "203.0.113.#{index}", "CF-Connecting-IP" => "203.0.113.#{index}" }, as: :json
      assert_response :accepted
    end
    post "/api/v1/auth/magic-links", params: { email: "missing@example.com" },
      headers: { "X-Forwarded-For" => "203.0.113.99", "CF-Connecting-IP" => "203.0.113.99" }, as: :json
    assert_error :too_many_requests, "rate_limited"
  end
end
