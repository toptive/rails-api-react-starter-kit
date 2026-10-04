require "test_helper"
require_relative "../support/settings_requests"

class SettingsEmailTest < ActionDispatch::IntegrationTest
  include SettingsRequests

  test "change email peek apply and sign in with the new address flow" do
    @owner.update!(locale: "es")
    old_email = @owner.email
    token = change_email(" New@example.com ")
    second = change_email("unused@example.com")
    mail = ActionMailer::Base.deliveries.first
    assert_equal [ "new@example.com" ], mail.to
    assert_equal I18n.t("mail.email_change.subject", app: "StarterKit", locale: :es), mail.subject
    assert_includes mail.html_part.body.decoded, 'lang="es"'
    assert_includes mail.text_part.body.decoded, "#{Rails.application.config.x.spa_origin}/settings/email-confirmations/#{token}"
    assert_nil mail["List-Unsubscribe"]
    assert_equal old_email, @owner.reload.email
    @scope.session.update!(sudo_until: nil)
    2.times do
      get "/api/v1/settings/email-confirmations/#{token}", headers: bearer(@owner_token)
      assert_response :ok
      assert_equal({ "email" => "new@example.com" }, data)
    end
    post "/api/v1/settings/email-confirmations", params: { token: token }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal "new@example.com", data.fetch("email")
    assert_empty @owner.user_tokens.where("context LIKE ?", "change_email:%")
    event = AuditEvent.find_by!(action: "user.email_changed", subject_id: @owner.id)
    assert_equal @owner.id, event.actor_id
    get "/api/v1/settings/email-confirmations/#{second}", headers: bearer(@owner_token)
    assert_error :unprocessable_entity, "email_change_invalid"
    post "/api/v1/settings/email-confirmations", params: { token: token }, headers: bearer(@owner_token), as: :json
    assert_error :unprocessable_entity, "email_change_invalid"
    post "/api/v1/auth/sessions", params: { email: old_email, password: "strong-password-123" }, as: :json
    assert_error :unauthorized, "invalid_credentials"
    post "/api/v1/auth/sessions", params: { email: "new@example.com", password: "strong-password-123" }, as: :json
    assert_response :created
    assert_equal @owner.id, data.dig("user", "id")
  end

  test "email change refuses unchanged address as a 409 field error" do
    assert_no_difference "UserToken.count" do
      put "/api/v1/settings/email", params: { email: " #{@owner.email.upcase} " }, headers: bearer(@owner_token), as: :json
    end
    assert_error :conflict, "email_unchanged"
    detail = response.parsed_body.dig("error", "details", "email", 0)
    assert_equal "validation.email_unchanged", detail.fetch("key")
    assert_equal I18n.t("validation.email_unchanged"), detail.fetch("message")
  end

  test "email change validates format length and uniqueness without writing tokens" do
    other = create_user
    [ [ "invalid", "validation.email_format" ], [ "a" * 155 + "@example.com", "validation.length_max" ],
      [ other.email.upcase, "validation.unique" ] ].each do |email, key|
      assert_no_difference "UserToken.count" do
        put "/api/v1/settings/email", params: { email: email }, headers: bearer(@owner_token), as: :json
      end
      assert_field_error "email", key, bindings: key == "validation.length_max" ? { "count" => 160 } : nil
    end
    assert_empty ActionMailer::Base.deliveries
  end

  test "email change rejects missing and wrong type fields" do
    [ {}, { email: nil }, { email: 7 } ].each do |attributes|
      put "/api/v1/settings/email", params: attributes, headers: bearer(@owner_token), as: :json
      assert_error :bad_request, "bad_request"
    end
  end

  test "email unavailable refuses before writing tokens or audit events" do
    previous = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :smtp
    ENV.delete("SMTP_ADDRESS")
    assert_no_difference [ "UserToken.count", "AuditEvent.count" ] do
      put "/api/v1/settings/email", params: { email: "new@example.com" }, headers: bearer(@owner_token), as: :json
    end
    assert_error :service_unavailable, "email_unavailable"
  ensure
    ActionMailer::Base.delivery_method = previous
  end

  test "email confirmation is bound to the user and rejects expired unknown or wrong context tokens" do
    other = create_user
    foreign = UserToken.issue_for(other, context: "change_email:#{other.email}", sent_to: "foreign@example.com")
    expired = UserToken.issue_for(@owner, context: "change_email:#{@owner.email}", sent_to: "expired@example.com")
    @owner.user_tokens.find_by!(sent_to: "expired@example.com").update!(expires_at: Time.current)
    stale = UserToken.issue_for(@owner, context: "change_email:old@example.com", sent_to: "stale@example.com")
    magic = UserToken.issue_for(@owner)
    [ "unknown", SecureRandom.urlsafe_base64(32), foreign, expired, stale, magic ].each do |token|
      get "/api/v1/settings/email-confirmations/#{token}", headers: bearer(@owner_token)
      assert_error :unprocessable_entity, "email_change_invalid"
      post "/api/v1/settings/email-confirmations", params: { token: token }, headers: bearer(@owner_token), as: :json
      assert_error :unprocessable_entity, "email_change_invalid"
    end
    assert_equal "Owner", @owner.reload.name
  end

  test "confirmation rejects an address that was claimed after the request" do
    token = change_email("claimed@example.com")
    create_user(email: "claimed@example.com")
    post "/api/v1/settings/email-confirmations", params: { token: token }, headers: bearer(@owner_token), as: :json
    assert_error :unprocessable_entity, "email_change_invalid"
    refute_equal "claimed@example.com", @owner.reload.email
    assert_equal 1, @owner.user_tokens.where("context LIKE ?", "change_email:%").count
  end

  test "confirmation rejects a missing or malformed token" do
    [ {}, { token: nil }, { token: 12 } ].each do |attributes|
      post "/api/v1/settings/email-confirmations", params: attributes, headers: bearer(@owner_token), as: :json
      assert_error :unprocessable_entity, "email_change_invalid"
    end
  end
end
