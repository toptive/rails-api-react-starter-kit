require "test_helper"
require_relative "../support/admin_requests"

class AdminImpersonationTest < ActionDispatch::IntegrationTest
  include AdminRequests

  test "impersonate act as the user and return to the original admin session flow" do
    target = create_user
    admin_session = Session.find_by_token(@admin_token)
    old_sudo_until = admin_session.sudo_until
    post "/api/v1/admin/users/#{target.id}/impersonation", params: { reason: "Investigate a support issue" }, headers: admin_headers, as: :json
    assert_response :created
    token = data.fetch("token")
    assert_equal target.id, data.dig("user", "id")
    assert_equal @admin.id, data.dig("impersonator", "id")
    assert_nil data.fetch("sudoUntil")
    assert_equal false, data.fetch("newAccount")
    refute data.key?("canManage")
    child = Session.find_by_token(token)
    assert_in_delta 8.hours.from_now.to_i, child.expires_at.to_i, 2
    assert_equal admin_session.id, child.impersonator_session_id
    assert_equal @admin.id, child.impersonator_id
    impersonation = child.impersonation
    assert_equal "Investigate a support issue", impersonation.reason
    started = AuditEvent.find_by!(action: "impersonation.started", subject_id: target.id)
    assert_equal @admin.id, started.actor_id
    assert_equal({ "reason" => impersonation.reason, "impersonationId" => impersonation.id }, started.metadata)
    get "/api/v1/bootstrap", headers: bearer(token)
    assert_equal false, data.dig("auth", "superadmin")
    assert_equal @admin.id, data.dig("auth", "impersonator", "id")
    assert_nil data.dig("auth", "sudoUntil")
    put "/api/v1/settings/email-preferences", params: { optionalEmails: false }, headers: bearer(token), as: :json
    assert_response :ok
    assert_equal false, target.reload.optional_emails
    event = AuditEvent.find_by!(action: "user.optional_emails_stopped", subject_id: target.id)
    assert_equal target.id, event.actor_id
    assert_equal @admin.id, event.impersonator_id
    assert_equal child.organization_id, event.organization_id
    delete "/api/v1/auth/impersonation", headers: bearer(token)
    assert_response :no_content
    assert impersonation.reload.ended_at
    assert_equal 1, AuditEvent.where(action: "impersonation.stopped", subject_id: impersonation.id).count
    get "/api/v1/bootstrap", headers: admin_headers
    assert_equal @admin.id, data.dig("auth", "user", "id")
    assert_equal true, data.dig("auth", "superadmin")
    assert_nil data.dig("auth", "impersonator")
    assert_equal old_sudo_until, admin_session.reload.sudo_until
    get "/api/v1/settings/email-preferences", headers: bearer(token)
    assert_error :unauthorized, "session_expired"
    get "/api/v1/admin/dashboard", headers: admin_headers
    assert_response :ok
  end

  test "self and superadmin targets are forbidden and absent users are not found" do
    [ @admin, create_user(role: "superadmin") ].each do |target|
      assert_no_difference [ "Impersonation.count", "Session.count", "AuditEvent.count" ] do
        post "/api/v1/admin/users/#{target.id}/impersonation", params: { reason: "Support investigation" }, headers: admin_headers, as: :json
      end
      assert_error :forbidden, "forbidden"
    end
    post "/api/v1/admin/users/#{SecureRandom.uuid}/impersonation", params: { reason: "Support investigation" }, headers: admin_headers, as: :json
    assert_error :not_found, "not_found"
  end

  test "reason must be a string between five and 255 characters" do
    target = create_user
    [ {}, { reason: 5 }, { reason: nil } ].each do |attributes|
      post "/api/v1/admin/users/#{target.id}/impersonation", params: attributes, headers: admin_headers, as: :json
      assert_error :bad_request, "bad_request"
    end
    [ [ "", "validation.required", nil ], [ "four", "validation.length_min", { "count" => 5 } ],
      [ "x" * 256, "validation.length_max", { "count" => 255 } ] ].each do |reason, key, bindings|
      assert_no_difference [ "Impersonation.count", "Session.count", "AuditEvent.count" ] do
        post "/api/v1/admin/users/#{target.id}/impersonation", params: { reason: reason }, headers: admin_headers, as: :json
      end
      assert_admin_field "reason", key, bindings: bindings
    end
    [ "a" * 5, "a" * 255 ].each do |reason|
      post "/api/v1/admin/users/#{target.id}/impersonation", params: { reason: reason }, headers: admin_headers, as: :json
      assert_response :created
    end
  end

  test "impersonation does not renew or grant sudo and expires at eight hours" do
    target = create_user
    post "/api/v1/admin/users/#{target.id}/impersonation", params: { reason: "Support investigation" }, headers: admin_headers, as: :json
    token = data.fetch("token")
    session = Session.find_by_token(token)
    original_expiry = session.expires_at
    post "/api/v1/auth/sudo", params: { password: "anything" }, headers: bearer(token), as: :json
    assert_error :forbidden, "forbidden"
    put "/api/v1/settings/password", params: { password: "new-password-123", passwordConfirmation: "new-password-123" }, headers: bearer(token), as: :json
    assert_error :forbidden, "sudo_required"
    travel 7.hours do
      get "/api/v1/bootstrap", headers: bearer(token)
      assert_response :ok
      assert_equal original_expiry, session.reload.expires_at
      assert_nil session.sudo_until
    end
    travel_to original_expiry + 1.second do
      get "/api/v1/settings/email-preferences", headers: bearer(token)
      assert_error :unauthorized, "session_expired"
    end
  end

  test "revoking the admin session revokes its impersonation sessions" do
    target = create_user
    post "/api/v1/admin/users/#{target.id}/impersonation", params: { reason: "Support investigation" }, headers: admin_headers, as: :json
    token = data.fetch("token")
    delete "/api/v1/auth/session", headers: admin_headers
    assert_response :no_content
    get "/api/v1/settings/email-preferences", headers: bearer(token)
    assert_error :unauthorized, "session_expired"
    assert Impersonation.find_by!(target_user: target).ended_at
  end
end
