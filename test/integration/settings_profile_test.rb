require "test_helper"
require_relative "../support/settings_requests"

class SettingsProfileTest < ActionDispatch::IntegrationTest
  include SettingsRequests

  test "profile updates name and supported locale and ignores protected fields" do
    put "/api/v1/settings/profile", params: { name: " New name ", locale: "es", role: "superadmin", email: "other@example.com", avatar: "ignored" },
      headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal "New name", data.fetch("name")
    assert_equal "es", data.fetch("locale")
    assert_equal "user", data.fetch("role")
    assert_equal @owner.email, data.fetch("email")
    assert_equal %w[confirmedAt email hasPassword id insertedAt locale name role], data.keys.sort
    get "/api/v1/bootstrap", headers: bearer(@owner_token)
    assert_equal "es", data.fetch("locale")
    assert_equal "New name", data.dig("auth", "user", "name")
  end

  [ [ { name: " " }, "name", "validation.required" ],
    [ { name: "x" * 121 }, "name", "validation.length_max" ],
    [ { locale: "fr" }, "locale", "validation.inclusion" ] ].each do |attributes, field, key|
    test "profile rejects #{key} for #{field}" do
      put "/api/v1/settings/profile", params: attributes, headers: bearer(@owner_token), as: :json
      assert_field_error field, key, bindings: key == "validation.length_max" ? { "count" => 120 } : nil
      assert_equal "Owner", @owner.reload.name
      assert_equal "en", @owner.locale
    end
  end

  test "profile rejects non string input" do
    put "/api/v1/settings/profile", params: { name: [] }, headers: bearer(@owner_token), as: :json
    assert_error :bad_request, "bad_request"
  end

  test "email preferences can be read disabled and enabled with exactly one audit per change" do
    get "/api/v1/settings/email-preferences", headers: bearer(@owner_token)
    assert_response :ok
    assert_equal({ "optionalEmails" => true }, data)
    [ false, false, true, true ].each do |value|
      put "/api/v1/settings/email-preferences", params: { optionalEmails: value }, headers: bearer(@owner_token), as: :json
      assert_response :ok
      assert_equal({ "optionalEmails" => value }, data)
    end
    %w[started stopped].each do |action|
      events = AuditEvent.where(action: "user.optional_emails_#{action}", subject_id: @owner.id)
      assert_equal 1, events.count
      assert_equal @owner.id, events.first.actor_id
    end
  end

  test "email preferences require a boolean and do not change on malformed input" do
    [ {}, { optionalEmails: nil }, { optionalEmails: 1 }, { optionalEmails: "yes" } ].each do |attributes|
      put "/api/v1/settings/email-preferences", params: attributes, headers: bearer(@owner_token), as: :json
      assert_error :bad_request, "bad_request"
      assert @owner.reload.optional_emails?
    end
  end

  test "settings mutate only the bearer user regardless of supplied ids" do
    other = create_user
    put "/api/v1/settings/profile", params: { name: "Ours", userId: other.id, organizationId: SecureRandom.uuid }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal @owner.id, data.fetch("id")
    put "/api/v1/settings/email-preferences", params: { optionalEmails: false, userId: other.id }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal "Ana", other.reload.name
    assert other.optional_emails?
  end
end
