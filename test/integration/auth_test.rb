require "test_helper"
require_relative "../support/auth_requests"

class AuthTest < ActionDispatch::IntegrationTest
  include AuthRequests

  test "register confirm sign in sudo and sign out flow" do
    travel_to Time.current.change(usec: 0)
    Rails.application.config.x.spa_origin = "https://app.example.com"
    perform_enqueued_jobs do
      post "/api/v1/auth/registrations?locale=es", params: {
        name: "Ana", email: " ANA@example.com ", termsAccepted: true, role: "superadmin", password: "ignored" }, as: :json
    end
    assert_response :accepted
    assert_equal({ "email" => "ana@example.com", "newAccount" => true }, data)
    user = User.find_by!(email: "ana@example.com")
    assert_nil user.confirmed_at
    assert_nil user.hashed_password
    assert_equal "user", user.role
    event = AuditEvent.find_by!(action: "user.registered", actor_id: user.id)
    assert_equal [], event.metadata.fetch("accepted")
    assert_equal Time.current, user.legal_accepted_at
    assert_equal "127.0.0.1", user.legal_accepted_ip_address
    assert_equal({}, user.legal_accepted_versions)
    assert_equal "127.0.0.1", event.ip_address
    email = ActionMailer::Base.deliveries.last
    assert_equal I18n.t("mail.magic_link.subject", app: "StarterKit", locale: :es), email.subject
    assert_includes email.html_part.body.decoded, 'lang="es"'
    assert_includes email.text_part.body.decoded, "https://app.example.com/magic-links/"
    raw = mail_token
    refute_includes performed_jobs.map { |job| job.fetch(:args) }.to_json, raw
    get "/api/v1/auth/magic-links/#{raw}"
    assert_equal({ "email" => user.email, "confirmed" => false }, data)
    post "/api/v1/auth/magic-links/#{raw}/session", as: :json
    assert_response :created
    assert data.fetch("newAccount")
    assert user.reload.confirmed_at
    # Password management is a separate API domain; provision one to exercise password auth.
    user.update!(password: "strong-password-123")
    token = sign_in(user)
    session = Session.find_by_token(token)
    session.update!(sudo_until: 1.second.ago)
    post "/api/v1/auth/sudo", params: { password: "strong-password-123" }, headers: bearer(token), as: :json
    assert_response :ok
    assert_equal 10.minutes.from_now.utc.iso8601, data.fetch("sudoUntil")
    assert AuditEvent.exists?(action: "user.sudo_authenticated", actor_id: user.id)
    delete "/api/v1/auth/session", headers: bearer(token)
    assert_response :no_content
    assert_empty response.body
    assert session.reload.revoked_at
    assert AuditEvent.exists?(action: "session.revoked", subject_id: session.id)
    post "/api/v1/auth/sudo", params: { password: "strong-password-123" }, headers: bearer(token), as: :json
    assert_error :unauthorized, "session_expired"
  end

  test "magic link request peek consume bootstrap flow" do
    user = create_user(locale: "es")
    raw = request_link(user)
    get "/api/v1/auth/magic-links/#{raw}"
    assert_response :ok
    assert_equal({ "email" => user.email, "confirmed" => true }, data)
    post "/api/v1/auth/magic-links/#{raw}/session", params: { rememberMe: false }, as: :json
    assert_response :created
    token = data.fetch("token")
    assert_equal false, data.fetch("newAccount")
    get "/api/v1/bootstrap", headers: bearer(token)
    assert_response :ok
    assert_equal user.id, data.dig("auth", "user", "id")
    assert_equal "es", data.fetch("locale")
    assert_equal 1, data.dig("auth", "organizations").length
    assert_equal true, data.dig("auth", "organization", "personal")
    assert_equal "owner", data.dig("auth", "membership", "role")
    assert_nil data.dig("auth", "membership", "user")
    assert_equal true, data.dig("auth", "onboardingRequired")
    assert_nil response.headers["Set-Cookie"]
  end

  test "authenticated bootstrap returns the current profile without locking rows" do
    user = create_user
    token = sign_in(user)
    user.update!(name: "Updated profile")
    queries = []
    capture = ->(event) { queries << event.payload[:sql] }

    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") do
      get "/api/v1/bootstrap", headers: bearer(token)
    end

    assert_response :ok
    assert_equal user.id, data.dig("auth", "user", "id")
    assert_equal "Updated profile", data.dig("auth", "user", "name")
    assert_empty queries.grep(/FOR (?:UPDATE|SHARE|NO KEY UPDATE|KEY SHARE)/i)
  end

  test "bootstrap refuses supplied invalid expired and revoked sessions so clients discard bearers" do
    user = create_user
    token = sign_in(user)
    get "/api/v1/bootstrap", headers: bearer("unknown")
    assert_error :unauthorized, "unauthorized"
    session = Session.find_by_token(token)
    session.update!(expires_at: 1.minute.ago)
    get "/api/v1/bootstrap", headers: bearer(token)
    assert_error :unauthorized, "session_expired"
    session.update!(expires_at: 1.day.from_now, revoked_at: Time.current)
    get "/api/v1/bootstrap", headers: bearer(token)
    assert_error :unauthorized, "session_expired"
    get "/api/v1/bootstrap"
    assert_response :ok
    assert_nil data.fetch("auth")
  end

  test "bootstrap anonymous and configured public flags" do
    get "/api/v1/bootstrap", headers: { "Accept-Language" => "es-AR" }
    assert_response :ok
    assert_nil data.fetch("auth")
    assert_equal "es", data.fetch("locale")
    assert_equal %w[en es], data.fetch("locales")
    assert_equal "open", data.dig("app", "signupMode")
    assert_equal true, data.dig("app", "emailAvailable")
    assert_equal false, data.dig("app", "googleEnabled")
    assert_equal({ "billing" => false }, data.fetch("flags"))
    assert_equal({ "required" => false, "siteKey" => nil }, data.fetch("turnstile"))
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "bootstrap honors locale precedence and suppresses superadmin while impersonating" do
    admin = create_user(role: "superadmin")
    token = sign_in(admin)
    get "/api/v1/bootstrap", headers: bearer(token)
    assert_equal true, data.dig("auth", "superadmin")
    target = create_user(locale: "es")
    row, raw, = impersonation_for(admin, target, Session.find_by_token(token))
    get "/api/v1/bootstrap?locale=en", headers: bearer(raw).merge("Accept-Language" => "es")
    assert_equal "en", data.fetch("locale")
    assert_equal false, data.dig("auth", "superadmin")
    assert_equal admin.id, data.dig("auth", "impersonator", "id")
    assert_nil data.dig("auth", "sudoUntil")
    assert_equal row.id, data.dig("auth", "sessionId")
  end

  test "registration validates name email locale and consent with translated field objects" do
    [ [ { name: "", email: "bad", termsAccepted: false }, %w[name email termsAccepted] ],
      [ { name: "x" * 121, email: "a@example.com", termsAccepted: true, locale: "fr" }, %w[name locale] ] ].each do |attrs, fields|
      assert_no_difference [ "User.count", "UserToken.count", "AuditEvent.count" ] do
        post "/api/v1/auth/registrations", params: attrs, as: :json
      end
      assert_error :unprocessable_entity, "validation_failed"
      fields.each do |field|
        details = response.parsed_body.dig("error", "details", field)
        assert details.present?, field
        assert details.first.fetch("key").start_with?("validation.")
        assert details.first.fetch("message").present?
      end
    end
  end

  test "registration duplicate email is case insensitive" do
    user = create_user
    post "/api/v1/auth/registrations", params: { name: "Ana", email: user.email.upcase, termsAccepted: true }, as: :json
    assert_error :unprocessable_entity, "validation_failed"
    assert_equal "validation.unique", response.parsed_body.dig("error", "details", "email", 0, "key")
  end

  test "signup closed and invite modes refuse before writes" do
    { "closed" => "signup_closed", "invite" => "invitation_required" }.each do |mode, code|
      ENV["SIGNUP_MODE"] = mode
      assert_no_difference [ "User.count", "UserToken.count", "AuditEvent.count" ] do
        post "/api/v1/auth/registrations", params: { name: "Ana", email: "a@example.com", termsAccepted: true }, as: :json
      end
      assert_error :unprocessable_entity, code
    end
  end

  test "email unavailable refuses registrations and magic link requests before writes" do
    previous_delivery = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :smtp
    ENV.delete("SMTP_ADDRESS")
    begin
      get "/api/v1/bootstrap"
      assert_equal false, data.dig("app", "emailAvailable")
      [ "/api/v1/auth/registrations", "/api/v1/auth/magic-links" ].each do |path|
        assert_no_difference [ "User.count", "UserToken.count", "AuditEvent.count" ] do
          post path, params: { name: "Ana", email: "a@example.com", termsAccepted: true }, as: :json
        end
        assert_error :service_unavailable, "email_unavailable"
      end
    ensure
      ActionMailer::Base.delivery_method = previous_delivery
    end
  end

  test "magic link requests never enumerate users and still work when signup is closed" do
    ENV["SIGNUP_MODE"] = "closed"
    user = create_user
    [ user.email, "unknown@example.com" ].each do |email|
      post "/api/v1/auth/magic-links", params: { email: email }, as: :json
      assert_response :accepted
      assert_equal({ "email" => email, "newAccount" => false }, data)
    end
    assert_equal 1, UserToken.where(user: user).count
    assert_equal 1, enqueued_jobs.size
  end

  test "peek and consume refuse malformed expired and already used links" do
    user = create_user
    raw = UserToken.issue_for(user)
    UserToken.where(user: user).update_all(expires_at: Time.current)
    [ "unknown", raw ].each do |token|
      get "/api/v1/auth/magic-links/#{token}"
      assert_error :unprocessable_entity, "magic_link_invalid"
      post "/api/v1/auth/magic-links/#{token}/session", as: :json
      assert_error :unprocessable_entity, "magic_link_invalid"
    end
    raw = UserToken.issue_for(user)
    post "/api/v1/auth/magic-links/#{raw}/session", as: :json
    assert_response :created
    get "/api/v1/auth/magic-links/#{raw}"
    assert_error :unprocessable_entity, "magic_link_invalid"
    post "/api/v1/auth/magic-links/#{raw}/session", as: :json
    assert_error :unprocessable_entity, "magic_link_invalid"
  end

  test "first confirmation invalidates other confirmation links but later sign in consumes only its link" do
    user = create_user(confirmed_at: nil)
    first, second = Array.new(2) { UserToken.issue_for(user) }
    post "/api/v1/auth/magic-links/#{first}/session", as: :json
    assert_response :created
    assert data.fetch("newAccount")
    get "/api/v1/auth/magic-links/#{second}"
    assert_error :unprocessable_entity, "magic_link_invalid"
    third, fourth = Array.new(2) { UserToken.issue_for(user) }
    post "/api/v1/auth/magic-links/#{third}/session", as: :json
    assert_response :created
    assert_equal false, data.fetch("newAccount")
    get "/api/v1/auth/magic-links/#{fourth}"
    assert_response :ok
  end

  test "links sent to an old email cannot sign in" do
    user = create_user
    raw = UserToken.issue_for(user)
    user.update!(email: "new@example.com")
    get "/api/v1/auth/magic-links/#{raw}"
    assert_error :unprocessable_entity, "magic_link_invalid"
    post "/api/v1/auth/magic-links/#{raw}/session", as: :json
    assert_error :unprocessable_entity, "magic_link_invalid"
  end

  test "password failures have the same response for missing wrong unconfirmed and passwordless accounts" do
    user = create_user(password: "strong-password-123")
    unconfirmed = create_user(password: "strong-password-123", confirmed_at: nil)
    passwordless = create_user
    [ [ user.email, "wrong" ], [ "missing@example.com", "strong-password-123" ],
      [ unconfirmed.email, "strong-password-123" ], [ passwordless.email, "strong-password-123" ] ].each do |email, password|
      assert_no_difference "Session.count" do
        post "/api/v1/auth/sessions", params: { email: email, password: password }, as: :json
      end
      assert_error :unauthorized, "invalid_credentials"
      assert_equal({}, response.parsed_body.dig("error", "details"))
    end
  end

  test "password and magic sign ins reuse the current session for the same user" do
    user = create_user
    token = sign_in(user)
    session = Session.find_by_token(token)
    session.update!(sudo_until: 1.minute.ago)
    assert_no_difference "Session.count" do
      post "/api/v1/auth/sessions", params: { email: user.email, password: "strong-password-123" }, headers: bearer(token), as: :json
    end
    assert_response :created
    assert_nil data.fetch("token")
    assert session.reload.sudo?
    raw = request_link(user, headers: bearer(token))
    assert_no_difference "Session.count" do
      post "/api/v1/auth/magic-links/#{raw}/session", headers: bearer(token), as: :json
    end
    assert_response :created
    assert_nil data.fetch("token")
  end

  test "signing in as a different user issues a separate token" do
    first, second = Array.new(2) { create_user(password: "strong-password-123") }
    token = sign_in(first)
    post "/api/v1/auth/sessions", params: { email: second.email, password: "strong-password-123" }, headers: bearer(token), as: :json
    assert_response :created
    refute_equal token, data.fetch("token")
    assert_equal second.id, data.dig("user", "id")
  end

  test "protected endpoints distinguish unknown expired and revoked sessions" do
    user = create_user
    token = sign_in(user)
    session = Session.find_by_token(token)
    [ "/api/v1/auth/session", "/api/v1/auth/impersonation" ].each do |path|
      delete path
      assert_error :unauthorized, "unauthorized"
    end
    post "/api/v1/auth/sudo", params: { password: "x" }, headers: bearer("invalid"), as: :json
    assert_error :unauthorized, "unauthorized"
    session.update!(expires_at: Time.current)
    delete "/api/v1/auth/session", headers: bearer(token)
    assert_error :unauthorized, "session_expired"
    session.update!(expires_at: 1.day.from_now, revoked_at: Time.current)
    delete "/api/v1/auth/session", headers: bearer(token)
    assert_error :unauthorized, "session_expired"
  end

  test "sudo validates password and passwordless accounts" do
    user = create_user
    raw = request_link(user)
    post "/api/v1/auth/magic-links/#{raw}/session", as: :json
    token = data.fetch("token")
    post "/api/v1/auth/sudo", params: { password: "x" }, headers: bearer(token), as: :json
    assert_error :unprocessable_entity, "validation_failed"
    assert_equal "validation.required", response.parsed_body.dig("error", "details", "password", 0, "key")
    user.update!(password: "strong-password-123")
    post "/api/v1/auth/sudo", params: { password: "wrong" }, headers: bearer(token), as: :json
    assert_error :unauthorized, "invalid_credentials"
  end

  test "sudo accepts only the current user's magic link without consuming another user's link" do
    user, other = Array.new(2) { create_user }
    token = sign_in(user)
    raw = UserToken.issue_for(other)
    post "/api/v1/auth/sudo", params: { magicLinkToken: raw }, headers: bearer(token), as: :json
    assert_error :unprocessable_entity, "magic_link_invalid"
    get "/api/v1/auth/magic-links/#{raw}"
    assert_response :ok
    raw = UserToken.issue_for(user)
    post "/api/v1/auth/sudo", params: { magicLinkToken: raw }, headers: bearer(token), as: :json
    assert_response :ok
    assert_match(/Z\z/, data.fetch("sudoUntil"))
    get "/api/v1/auth/magic-links/#{raw}"
    assert_error :unprocessable_entity, "magic_link_invalid"
  end

  test "ending a normal session's impersonation returns conflict" do
    token = sign_in(create_user)
    delete "/api/v1/auth/impersonation", headers: bearer(token)
    assert_error :conflict, "conflict"
    assert_equal "not_impersonating", response.parsed_body.dig("error", "details", "reason")
  end

  test "ending impersonation preserves the admin session and records the end" do
    admin = create_user(role: "superadmin")
    admin_session = Session.find_by_token(sign_in(admin))
    row, raw, impersonation = impersonation_for(admin, create_user, admin_session)
    post "/api/v1/auth/sudo", params: { password: "x" }, headers: bearer(raw), as: :json
    assert_error :forbidden, "forbidden"
    delete "/api/v1/auth/impersonation", headers: bearer(raw)
    assert_response :no_content
    assert row.reload.revoked_at
    assert impersonation.reload.ended_at
    assert admin_session.reload.live?
    event = AuditEvent.find_by!(action: "impersonation.stopped", subject_id: impersonation.id)
    assert_equal admin.id, event.impersonator_id
  end

  test "sign out while impersonating revokes both tokens" do
    admin = create_user(role: "superadmin")
    admin_session = Session.find_by_token(sign_in(admin))
    row, raw, impersonation = impersonation_for(admin, create_user, admin_session)
    delete "/api/v1/auth/session", headers: bearer(raw)
    assert_response :no_content
    assert row.reload.revoked_at
    assert admin_session.reload.revoked_at
    assert impersonation.reload.ended_at
  end

  test "revoking an admin session revokes child impersonation sessions" do
    admin = create_user(role: "superadmin")
    raw = sign_in(admin)
    admin_session = Session.find_by_token(raw)
    child, = impersonation_for(admin, create_user, admin_session)
    delete "/api/v1/auth/session", headers: bearer(raw)
    assert_response :no_content
    assert child.reload.revoked_at
  end

  test "missing required top level fields use the bad request envelope" do
    [ [ "/api/v1/auth/registrations", { name: "Ana", email: "a@example.com" }, "termsAccepted" ],
      [ "/api/v1/auth/magic-links", {}, "email" ],
      [ "/api/v1/auth/sessions", { email: "a@example.com" }, "password" ] ].each do |path, attributes, field|
      post path, params: attributes, as: :json
      assert_error :bad_request, "bad_request"
      assert_equal "validation.required", response.parsed_body.dig("error", "details", field, 0, "key")
    end
  end

  test "malformed scalar types use a 400 envelope without writes" do
    [ { name: 123, email: "a@example.com", termsAccepted: true },
      { name: "Ana", email: true, termsAccepted: true },
      { name: "Ana", email: "a@example.com", termsAccepted: 123 } ].each do |attributes|
      assert_no_difference "User.count" do
        post "/api/v1/auth/registrations", params: attributes, as: :json
      end
      assert_error :bad_request, "bad_request"
    end
  end

  test "form encoded requests return a 415 envelope" do
    post "/api/v1/auth/sessions", params: { email: "a@example.com", password: "password" }
    assert_error :unsupported_media_type, "unsupported_media_type"
  end

  private

  def impersonation_for(admin, target, admin_session)
    impersonation = Impersonation.create!(admin: admin, target_user: target, reason: "Support request")
    raw = SecureRandom.urlsafe_base64(32)
    row = Session.create!(user: target, token_hash: Digest::SHA256.digest(raw), expires_at: 8.hours.from_now,
      authenticated_at: Time.current, impersonator_user: admin, impersonator_session: admin_session,
      impersonation: impersonation)
    [ row, raw, impersonation ]
  end
end
