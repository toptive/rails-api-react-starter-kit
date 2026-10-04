require "test_helper"
require_relative "../support/settings_requests"

class SettingsPasswordTest < ActionDispatch::IntegrationTest
  include SettingsRequests

  test "password rotates the device revokes other sessions and all user tokens flow" do
    second_token = sign_in(@owner)
    UserToken.issue_for(@owner)
    UserToken.issue_for(@owner, context: "change_email:#{@owner.email}", sent_to: "new@example.com")
    other = create_user
    other_token = sign_in(other)
    UserToken.issue_for(other)
    put "/api/v1/settings/password", params: { password: "updated-password-123", passwordConfirmation: "updated-password-123" },
      headers: bearer(@owner_token).merge("User-Agent" => "Settings device"), as: :json
    assert_response :ok
    fresh = data.fetch("token")
    assert fresh
    refute_equal @owner_token, fresh
    assert_equal true, data.dig("user", "hasPassword")
    assert_equal false, data.fetch("newAccount")
    assert_nil data.fetch("impersonator")
    assert_equal @owner.id, data.dig("user", "id")
    assert Time.iso8601(data.fetch("sudoUntil")) > Time.current
    assert_empty @owner.user_tokens
    assert_equal 1, other.user_tokens.count
    assert Session.find_by_token(other_token)
    [ @owner_token, second_token ].each do |token|
      get "/api/v1/settings/sessions", headers: bearer(token)
      assert_error :unauthorized, "session_expired"
    end
    get "/api/v1/settings/sessions", headers: bearer(fresh)
    assert_response :ok
    assert_equal 1, data.length
    assert_equal true, data.first.fetch("current")
    assert_equal "Settings device", data.first.fetch("userAgent")
    assert_equal @organization.id, Session.find_by_token(fresh).organization_id
    assert_equal 1, AuditEvent.where(action: "user.password_changed", actor_id: @owner.id, subject_id: @owner.id).count
    revoked_ids = AuditEvent.where(action: "session.revoked", actor_id: @owner.id).pluck(:subject_id)
    refute_includes revoked_ids, @scope.session.id
    assert_includes revoked_ids, Session.find_by(token_hash: Digest::SHA256.digest(second_token)).id
    post "/api/v1/auth/sessions", params: { email: @owner.email, password: "strong-password-123" }, as: :json
    assert_error :unauthorized, "invalid_credentials"
    post "/api/v1/auth/sessions", params: { email: @owner.email, password: "updated-password-123" }, as: :json
    assert_response :created
  end

  test "a passwordless confirmed account can set its first password" do
    @owner.update!(hashed_password: nil)
    put "/api/v1/settings/password", params: { password: "first-password-123", passwordConfirmation: "first-password-123" }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal true, data.dig("user", "hasPassword")
  end

  [ [ "short", "validation.length_min", { "count" => 12 } ],
    [ "a" * 73, "validation.length_max", { "count" => 72 } ],
    [ "é" * 37, "validation.length_max", { "count" => 72 } ] ].each do |password, key, bindings|
    test "password validates #{key} for #{password.bytesize} bytes before any revocation" do
      token = UserToken.issue_for(@owner)
      assert_no_difference [ "Session.count", "AuditEvent.count" ] do
        put "/api/v1/settings/password", params: { password: password, passwordConfirmation: password }, headers: bearer(@owner_token), as: :json
      end
      assert_field_error "password", key, bindings: bindings
      assert @scope.session.reload.live?
      assert UserToken.magic_link(token)
      assert User.password_matches?(@owner.reload, "strong-password-123")
    end
  end

  test "password length is measured in bytes and accepts the twelve and seventy two byte boundaries" do
    [ "é" * 6, "a" * 72 ].each do |password|
      put "/api/v1/settings/password", params: { password: password, passwordConfirmation: password }, headers: bearer(@owner_token), as: :json
      assert_response :ok
      @owner_token = data.fetch("token")
      assert User.password_matches?(@owner.reload, password)
    end
  end

  test "password confirmation mismatch is a translated field error with no writes" do
    put "/api/v1/settings/password", params: { password: "updated-password-123", passwordConfirmation: "different-password" }, headers: bearer(@owner_token), as: :json
    assert_field_error "passwordConfirmation", "validation.password_mismatch"
    assert @scope.session.reload.live?
    assert User.password_matches?(@owner.reload, "strong-password-123")
  end

  test "password and confirmation are required strings" do
    [ {}, { password: "updated-password-123" }, { password: 12, passwordConfirmation: "same" },
      { password: "updated-password-123", passwordConfirmation: nil } ].each do |attributes|
      put "/api/v1/settings/password", params: attributes, headers: bearer(@owner_token), as: :json
      assert_error :bad_request, "bad_request"
    end
  end
end
