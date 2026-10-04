require "test_helper"
require_relative "../support/settings_requests"

class SettingsRateLimitsTest < ActionDispatch::IntegrationTest
  include SettingsRequests

  test "email change is five per minute per user shared across devices and isolated from another user on the same IP" do
    second_token = sign_in(@owner)
    5.times do |index|
      token = index.even? ? @owner_token : second_token
      put "/api/v1/settings/email", params: { email: "new#{index}@example.com" }, headers: bearer(token), as: :json
      assert_response :accepted
    end
    assert_no_difference "UserToken.count" do
      put "/api/v1/settings/email", params: { email: "limited@example.com" }, headers: bearer(@owner_token), as: :json
    end
    assert_rate_limited
    other_token = sign_in(create_user)
    put "/api/v1/settings/email", params: { email: "different@example.com" }, headers: bearer(other_token), as: :json
    assert_response :accepted
    travel 61.seconds
    put "/api/v1/settings/email", params: { email: "after@example.com" }, headers: bearer(@owner_token), as: :json
    assert_response :accepted
  end

  test "email confirmation accepts ten attempts per minute then refuses with retry metadata" do
    10.times do
      post "/api/v1/settings/email-confirmations", params: { token: "missing" }, headers: bearer(@owner_token), as: :json
      assert_error :unprocessable_entity, "email_change_invalid"
    end
    post "/api/v1/settings/email-confirmations", params: { token: "missing" }, headers: bearer(@owner_token), as: :json
    assert_rate_limited
    get "/api/v1/settings/email-confirmations/missing", headers: bearer(@owner_token)
    assert_error :unprocessable_entity, "email_change_invalid"
    travel 61.seconds
    post "/api/v1/settings/email-confirmations", params: { token: "missing" }, headers: bearer(@owner_token), as: :json
    assert_error :unprocessable_entity, "email_change_invalid"
  end

  test "account deletion accepts five attempts per IP then refuses while preview remains readable" do
    signed_member
    5.times do
      delete "/api/v1/settings/account", headers: bearer(@owner_token)
      assert_error :conflict, "transfer_ownership"
    end
    delete "/api/v1/settings/account", headers: bearer(@owner_token)
    assert_rate_limited
    get "/api/v1/settings/account", headers: bearer(@owner_token)
    assert_response :ok
    other_token = sign_in(create_user)
    delete "/api/v1/settings/account", headers: bearer(other_token)
    assert_rate_limited
    travel 61.seconds
    delete "/api/v1/settings/account", headers: bearer(@owner_token)
    assert_error :conflict, "transfer_ownership"
  end

  private

  def assert_rate_limited
    assert_error :too_many_requests, "rate_limited"
    assert_equal "60", response.headers["Retry-After"]
    assert_equal({ "retryAfter" => 60 }, response.parsed_body.dig("error", "details"))
  end
end
