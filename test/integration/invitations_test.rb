require "test_helper"
require_relative "../support/tenancy_requests"

class InvitationsTest < ActionDispatch::IntegrationTest
  include TenancyRequests

  test "invitation mail uses request locale branded layout and encrypted queue arguments" do
    travel_to Time.current.change(usec: 0)
    Rails.application.config.x.spa_origin = "https://app.example.com"
    ENV["MAIL_FROM_ES"] = "hola@example.com"
    id, raw = invite(" INVITEE@example.com ", role: "admin", access: "viewer", headers: bearer(@owner_token).merge("Accept-Language" => "es-AR"))
    assert_equal %w[access email expiresAt id insertedAt role], data.keys.sort
    assert_equal "invitee@example.com", data.fetch("email")
    assert_equal 7.days.from_now.utc.iso8601, data.fetch("expiresAt")
    invitation = Invitation.for(@scope).find(id)
    assert_equal Digest::SHA256.digest(raw), invitation.token_hash
    refute_equal raw, invitation.token_hash
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "hola@example.com" ], mail.from
    assert_equal "invitation", mail["X-Email-Kind"].value
    assert_equal I18n.t("mail.invitation.subject", inviter: @owner.name, organization: @organization.name, locale: :es), mail.subject
    assert_includes mail.html_part.body.decoded, 'lang="es"'
    assert_includes mail.text_part.body.decoded, "https://app.example.com/invitations/#{raw}"
    assert_nil mail["List-Unsubscribe"]
    refute_includes performed_jobs.map { |job| job.fetch(:args) }.to_json, raw
    assert_equal "default", performed_jobs.find { |job| job[:job] == InvitationDeliveryJob }.fetch(:queue)
  ensure
    ENV.delete("MAIL_FROM_ES")
  end

  test "list contains only pending invitations newest first without tokens" do
    first, = invite("first@example.com")
    travel 1.second
    second, = invite("second@example.com")
    expired, = invite("expired@example.com")
    accepted, = invite("accepted@example.com")
    Invitation.for(@scope).find(expired).update!(expires_at: Time.current)
    Invitation.for(@scope).find(accepted).update!(accepted_at: Time.current)
    get "/api/v1/settings/invitations", headers: bearer(@owner_token)
    assert_response :ok
    assert_equal [ second, first ], data.pluck("id")
    refute_includes response.body, "token"
  end

  test "preview works anonymously and personalizes an optional bearer without consuming the invitation" do
    guest = create_user
    id, raw = invite(guest.email)
    get "/api/v1/invitations/#{raw}"
    assert_response :ok
    assert_equal({ "organization" => @organization.name, "email" => guest.email, "role" => "member", "access" => "full",
      "emailMatches" => false, "expiresAt" => Invitation.for(@scope).find(id).expires_at.utc.iso8601 }, data)
    get "/api/v1/invitations/#{raw}", headers: bearer(@owner_token)
    assert_equal false, data.fetch("emailMatches")
    token = sign_in(guest)
    get "/api/v1/invitations/#{raw}", headers: bearer(token)
    assert_equal true, data.fetch("emailMatches")
    get "/api/v1/invitations/#{raw}", headers: bearer("invalid")
    assert_equal false, data.fetch("emailMatches")
    assert_nil Invitation.for(@scope).find(id).accepted_at
  end

  test "accepted expired revoked unknown and malformed tokens fail preview and acceptance" do
    guest = create_user
    token = sign_in(guest)
    accepted_id, accepted_raw = invite(guest.email)
    post "/api/v1/invitations/#{accepted_raw}/acceptance", headers: bearer(token), as: :json
    assert_response :created
    assert Invitation.for(@scope).find(accepted_id).accepted_at
    expired_id, expired_raw = invite("expired@example.com")
    Invitation.for(@scope).find(expired_id).update!(expires_at: Time.current)
    revoked_id, revoked_raw = invite("revoked@example.com")
    delete "/api/v1/settings/invitations/#{revoked_id}", headers: bearer(@owner_token)
    assert_response :no_content
    assert AuditEvent.exists?(action: "invitation.revoked", subject_id: revoked_id)
    [ accepted_raw, expired_raw, revoked_raw, SecureRandom.urlsafe_base64(32), "invalid" ].each do |raw|
      get "/api/v1/invitations/#{raw}"
      assert_error :unprocessable_entity, "invitation_invalid"
      post "/api/v1/invitations/#{raw}/acceptance", headers: bearer(token), as: :json
      assert_error :unprocessable_entity, "invitation_invalid"
    end
  end

  test "email mismatch refuses acceptance and does not consume the invitation or switch the device" do
    id, raw = invite("someone-else@example.com")
    post "/api/v1/invitations/#{raw}/acceptance", headers: bearer(@owner_token), as: :json
    assert_error :conflict, "email_mismatch"
    assert_equal({ "email" => "someone-else@example.com" }, response.parsed_body.dig("error", "details"))
    assert_nil Invitation.for(@scope).find(id).accepted_at
    assert_equal @organization.id, @scope.session.reload.organization_id
    refute AuditEvent.exists?(action: "invitation.accepted", subject_id: id)
  end

  test "accepting when already a member preserves the existing role and access" do
    guest = create_user
    id, raw = invite(guest.email, role: "admin", access: "full")
    member = seat(guest, role: "member", access: "viewer")
    token = sign_in(guest)
    assert_no_difference "Membership.for(@scope).count" do
      post "/api/v1/invitations/#{raw}/acceptance", headers: bearer(token), as: :json
    end
    assert_response :created
    assert_equal member.id, data.fetch("id")
    assert_equal "member", data.fetch("role")
    assert_equal "viewer", data.fetch("access")
    assert_equal guest.id, data.dig("user", "id")
    assert Invitation.for(@scope).find(id).accepted_at
  end

  test "create validates email role access existing seats and duplicate invitations" do
    [ [ { email: "invalid" }, "email", "validation.email_format" ],
      [ { email: "ok@example.com", role: "owner" }, "role", "validation.invitation_owner" ],
      [ { email: "ok@example.com", role: "invalid" }, "role", "validation.inclusion" ],
      [ { email: "ok@example.com", access: "invalid" }, "access", "validation.inclusion" ],
      [ { email: @owner.email }, "email", "validation.already_member" ] ].each do |attributes, field, key|
      assert_no_difference "Invitation.for(@scope).count" do
        post "/api/v1/settings/invitations", params: attributes, headers: bearer(@owner_token), as: :json
      end
      assert_field_error field, key
    end
    invite("duplicate@example.com")
    assert_no_enqueued_jobs only: InvitationDeliveryJob do
      post "/api/v1/settings/invitations", params: { email: " DUPLICATE@example.com " }, headers: bearer(@owner_token), as: :json
    end
    assert_field_error "email", "validation.invitation_pending"
    [ {}, { email: 42 }, { email: "ok@example.com", role: [] } ].each do |attributes|
      post "/api/v1/settings/invitations", params: attributes, headers: bearer(@owner_token), as: :json
      assert_error :bad_request, "bad_request"
    end
  end

  test "an expired pending email can be invited again and the old token no longer works" do
    id, raw = invite("repeat@example.com")
    Invitation.for(@scope).find(id).update!(expires_at: Time.current)
    replacement, = invite(" REPEAT@example.com ")
    refute_equal id, replacement
    get "/api/v1/invitations/#{raw}"
    assert_error :unprocessable_entity, "invitation_invalid"
  end

  test "unavailable mail refuses creation before any write or enqueue" do
    previous = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :smtp
    ENV.delete("SMTP_ADDRESS")
    before_events = AuditEvent.count
    assert_no_difference "Invitation.for(@scope).count" do
      assert_no_enqueued_jobs only: InvitationDeliveryJob do
        post "/api/v1/settings/invitations", params: { email: "new@example.com" }, headers: bearer(@owner_token), as: :json
      end
    end
    assert_error :service_unavailable, "email_unavailable"
    assert_equal before_events, AuditEvent.count
  ensure
    ActionMailer::Base.delivery_method = previous
  end

  test "invite signup mode checks real open invitations and expires them" do
    id, = invite("invited@example.com")
    ENV["SIGNUP_MODE"] = "invite"
    post "/api/v1/auth/registrations", params: { name: "New member", email: " INVITED@example.com ", termsAccepted: true }, as: :json
    assert_response :accepted
    assert User.exists?(email: "invited@example.com")
    Invitation.for(@scope).find(id).update!(expires_at: Time.current)
    post "/api/v1/auth/registrations", params: { name: "New member", email: "invited@example.com", termsAccepted: true }, as: :json
    assert_error :unprocessable_entity, "invitation_required"
    post "/api/v1/auth/registrations", params: { name: "No invitation", email: "uninvited@example.com", termsAccepted: true }, as: :json
    assert_error :unprocessable_entity, "invitation_required"
    refute User.exists?(email: "uninvited@example.com")
  end

  test "revoking a missing id returns not found" do
    [ SecureRandom.uuid, "invalid" ].each do |id|
      delete "/api/v1/settings/invitations/#{id}", headers: bearer(@owner_token)
      assert_error :not_found, "not_found"
    end
  end

  test "invitation create rate limit is thirty per hour per client IP" do
    30.times do
      post "/api/v1/settings/invitations", params: { email: "rate@example.com" }, headers: bearer(@owner_token), as: :json
      assert_includes [ 201, 422 ], response.status
    end
    post "/api/v1/settings/invitations", params: { email: "rate@example.com" }, headers: bearer(@owner_token), as: :json
    assert_error :too_many_requests, "rate_limited"
    travel 1.hour + 1.second
    post "/api/v1/settings/invitations", params: { email: "after@example.com" }, headers: bearer(@owner_token), as: :json
    assert_response :created
  end
end
