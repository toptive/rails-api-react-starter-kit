require "test_helper"
require_relative "../support/settings_requests"

class SettingsSessionsTest < ActionDispatch::IntegrationTest
  include SettingsRequests

  test "devices are all live user sessions newest first without impersonation or bearer hashes" do
    @scope.session.update!(created_at: 1.day.ago)
    second_token = sign_in(@owner)
    second = Session.find_by_token(second_token)
    expired = @scope.session.dup
    expired.assign_attributes(token_hash: Digest::SHA256.digest(SecureRandom.urlsafe_base64(32)), expires_at: 1.day.ago)
    expired.save!
    revoked = expired.dup
    revoked.assign_attributes(token_hash: Digest::SHA256.digest(SecureRandom.urlsafe_base64(32)), expires_at: 1.day.from_now, revoked_at: Time.current)
    revoked.save!
    impersonation = second.dup
    impersonation.assign_attributes(token_hash: Digest::SHA256.digest(SecureRandom.urlsafe_base64(32)), impersonator_user: create_user(role: "superadmin"), sudo_until: nil)
    impersonation.save!
    other_token = sign_in(create_user)
    get "/api/v1/settings/sessions", headers: bearer(@owner_token)
    assert_response :ok
    assert_equal [ second.id, @scope.session.id ], data.pluck("id")
    assert_equal [ false, true ], data.pluck("current")
    assert_equal({}, response.parsed_body.fetch("meta"))
    assert_equal %w[authenticatedAt current id insertedAt ipAddress userAgent], data.first.keys.sort
    assert_equal "127.0.0.1", data.first.fetch("ipAddress")
    assert data.all? { |session| session.fetch("insertedAt").end_with?("Z") }
    refute_includes response.body, second_token
    refute_includes response.body, Session.find_by_token(other_token).id
    # No pagination: all devices are returned even if there are more than 25.
    26.times do
      row = second.dup
      row.token_hash = Digest::SHA256.digest(SecureRandom.urlsafe_base64(32))
      row.save!
    end
    get "/api/v1/settings/sessions", headers: bearer(@owner_token)
    assert_equal 28, data.length
  end

  test "revoke another device audits once and its known token returns session expired" do
    token = sign_in(@owner)
    session = Session.find_by_token(token)
    2.times do
      delete "/api/v1/settings/sessions/#{session.id}", headers: bearer(@owner_token)
      assert_response :no_content
      assert_empty response.body
    end
    assert_equal 1, AuditEvent.where(action: "session.revoked", subject_id: session.id).count
    get "/api/v1/settings/sessions", headers: bearer(token)
    assert_error :unauthorized, "session_expired"
    get "/api/v1/settings/sessions", headers: bearer(@owner_token)
    assert_equal [ @scope.session.id ], data.pluck("id")
  end

  test "revoke current device ends the caller session" do
    delete "/api/v1/settings/sessions/#{@scope.session.id}", headers: bearer(@owner_token)
    assert_response :no_content
    get "/api/v1/settings/email-preferences", headers: bearer(@owner_token)
    assert_error :unauthorized, "session_expired"
  end

  test "another user's device and unknown ids return 404 without revocation" do
    token = sign_in(create_user)
    session = Session.find_by_token(token)
    [ session.id, SecureRandom.uuid, "not-a-uuid" ].each do |id|
      delete "/api/v1/settings/sessions/#{id}", headers: bearer(@owner_token)
      assert_error :not_found, "not_found"
    end
    assert session.reload.live?
  end
end
