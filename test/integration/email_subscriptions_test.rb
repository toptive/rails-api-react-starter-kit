require "test_helper"
require_relative "../support/auth_requests"

class EmailSubscriptionsTest < ActionDispatch::IntegrationTest
  include AuthRequests

  test "preview does not unsubscribe and tokens have no expiry" do
    user = create_user
    token = EmailSubscription.token_for(user)
    travel 10.years
    get "/api/v1/email-subscriptions/#{token}"
    assert_response :ok
    assert_equal({ "email" => user.email, "subscribed" => true }, data)
    assert user.reload.optional_emails?
    refute AuditEvent.exists?(action: "user.optional_emails_stopped", subject_id: user.id)
  end

  test "JSON opt out is idempotent audits once and requires no bearer" do
    user = create_user
    token = EmailSubscription.token_for(user)
    2.times do
      post "/api/v1/email-subscriptions/#{token}/opt-out", params: {}, as: :json
      assert_response :ok
      assert_equal({ "email" => user.email, "subscribed" => false }, data)
    end
    assert_equal false, user.reload.optional_emails
    assert_equal 1, AuditEvent.where(action: "user.optional_emails_stopped", subject_id: user.id).count
    event = AuditEvent.find_by!(action: "user.optional_emails_stopped", subject_id: user.id)
    assert_equal user.id, event.actor_id
    assert_equal "127.0.0.1", event.ip_address
    get "/api/v1/email-subscriptions/#{token}"
    assert_equal false, data.fetch("subscribed")
  end

  test "RFC 8058 one click form returns a bare 200 and rejects a malformed form" do
    user = create_user
    token = EmailSubscription.token_for(user)
    post "/api/v1/email-subscriptions/#{token}/opt-out", params: { "List-Unsubscribe" => "wrong" }
    assert_error :bad_request, "bad_request"
    assert user.reload.optional_emails?
    post "/api/v1/email-subscriptions/#{token}/opt-out", params: { "List-Unsubscribe" => "One-Click" }
    assert_response :ok
    assert_empty response.body
    assert_nil response.headers["Set-Cookie"]
    assert_equal false, user.reload.optional_emails
    post "/api/v1/email-subscriptions/#{token}/opt-out", params: "payload", headers: { "Content-Type" => "text/plain" }
    assert_error :unsupported_media_type, "unsupported_media_type"
  end

  test "unknown tampered deleted user and email changed tokens return the error envelope" do
    changed = create_user
    changed_token = EmailSubscription.token_for(changed)
    changed.update!(email: "changed@example.com")
    deleted = create_user
    deleted_token = EmailSubscription.token_for(deleted)
    deleted.destroy!
    valid = EmailSubscription.token_for(create_user)
    [ "missing", valid + "tampered", changed_token, deleted_token ].each do |token|
      get "/api/v1/email-subscriptions/#{token}"
      assert_error :not_found, "not_found"
      post "/api/v1/email-subscriptions/#{token}/opt-out", params: {}, as: :json
      assert_error :not_found, "not_found"
      post "/api/v1/email-subscriptions/#{token}/opt-out", params: { "List-Unsubscribe" => "One-Click" }
      assert_error :not_found, "not_found"
    end
    assert changed.reload.optional_emails?
  end

  test "opt out rate limit accepts 120 calls per minute then refuses" do
    user = create_user
    token = EmailSubscription.token_for(user)
    120.times do
      post "/api/v1/email-subscriptions/#{token}/opt-out", params: {}, as: :json
      assert_response :ok
    end
    post "/api/v1/email-subscriptions/#{token}/opt-out", params: {}, as: :json
    assert_error :too_many_requests, "rate_limited"
    get "/api/v1/email-subscriptions/#{token}"
    assert_response :ok
  end
end
