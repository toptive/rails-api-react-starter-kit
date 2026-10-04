require "test_helper"
require_relative "../support/settings_requests"

class SettingsAccountTest < ActionDispatch::IntegrationTest
  include SettingsRequests

  test "preview blocks the last owner with another member then deletion is allowed after transfer" do
    colleague, token, membership = signed_member
    get "/api/v1/settings/account", headers: bearer(@owner_token)
    assert_response :ok
    assert_equal({ "blocker" => { "reason" => "transfer_ownership", "organization" => @organization.name } }, data)
    assert_no_difference [ "User.count", "Membership.for(@scope).count", "Session.count", "AuditEvent.count" ] do
      delete "/api/v1/settings/account", headers: bearer(@owner_token)
    end
    assert_error :conflict, "transfer_ownership"
    assert_equal({ "organization" => @organization.name }, response.parsed_body.dig("error", "details"))
    put "/api/v1/settings/members/#{membership.id}", params: { role: "owner" }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    get "/api/v1/settings/account", headers: bearer(@owner_token)
    assert_response :ok
    assert_nil data.fetch("blocker")
    delete "/api/v1/settings/account", headers: bearer(@owner_token)
    assert_response :no_content
    assert_empty response.body
    refute User.exists?(@owner.id)
    assert Organization.exists?(@organization.id)
    assert_equal [ colleague.id ], Membership.for(@scope).pluck(:user_id)
    get "/api/v1/settings/members", headers: bearer(token)
    assert_response :ok
    assert_equal [ colleague.id ], data.map { |member| member.dig("user", "id") }
    event = AuditEvent.find_by!(action: "user.deleted", subject_id: @owner.id)
    assert_equal @owner.id, event.actor_id
  end

  test "sole member deletion cascades sessions tokens memberships and empty organizations but retains legal acceptance" do
    email = "registered@example.com"
    perform_enqueued_jobs do
      post "/api/v1/auth/registrations", params: { name: "Registered", email: email, termsAccepted: true }, as: :json
    end
    assert_response :accepted
    post "/api/v1/auth/magic-links/#{mail_token}/session", params: {}, as: :json
    assert_response :created
    token = data.fetch("token")
    user = User.find(data.dig("user", "id"))
    other_token = sign_in(user)
    scope = Session.scope_for(Session.find_by_token(token))
    UserToken.issue_for(user)
    UserToken.issue_for(user, context: "change_email:#{email}", sent_to: "pending@example.com")
    acceptance = LegalAcceptance.find_by!(user: user)
    delete "/api/v1/settings/account", headers: bearer(token)
    assert_response :no_content
    refute User.exists?(user.id)
    refute Session.exists?(user_id: user.id)
    refute UserToken.exists?(user_id: user.id)
    refute Organization.exists?(scope.organization.id)
    assert_nil acceptance.reload.user_id
    assert_equal Digest::SHA256.hexdigest(email), acceptance.email_hash
    assert_equal({}, acceptance.versions)
    assert acceptance.accepted_at
    assert_equal "127.0.0.1", acceptance.ip_address
    assert AuditEvent.exists?(action: "organization.deleted", subject_id: scope.organization.id)
    [ token, other_token ].each do |bearer_token|
      get "/api/v1/settings/sessions", headers: bearer(bearer_token)
      assert_error :unauthorized, "unauthorized"
    end
  end

  test "any subscription that can charge in either mode blocks the sole member even with billing disabled" do
    %w[active trialing past_due unpaid incomplete paused unknown].product([ false, true ]).each do |status, live|
      Api::V1::BaseController::RATE_LIMIT_STORE.clear
      subscription = Subscription.for(@scope).create!(status: status, livemode: live)
      get "/api/v1/settings/account", headers: bearer(@owner_token)
      assert_response :ok
      assert_equal({ "reason" => "subscription_active", "organization" => @organization.name }, data.fetch("blocker"))
      assert_no_difference [ "User.count", "Membership.for(@scope).count", "AuditEvent.count" ] do
        delete "/api/v1/settings/account", headers: bearer(@owner_token)
      end
      assert_error :conflict, "subscription_active"
      assert_equal({ "organization" => @organization.name }, response.parsed_body.dig("error", "details"))
      subscription.destroy!
    end
  end

  test "closed subscription history in either mode permits deletion but retains the empty organization" do
    Subscription.for(@scope).create!(status: "canceled", livemode: false)
    Subscription.for(@scope).create!(status: "incomplete_expired", livemode: true)
    get "/api/v1/settings/account", headers: bearer(@owner_token)
    assert_response :ok
    assert_nil data.fetch("blocker")
    delete "/api/v1/settings/account", headers: bearer(@owner_token)
    assert_response :no_content
    assert Organization.exists?(@organization.id)
    assert_empty Membership.for(@scope)
    assert_equal 2, Subscription.for(@scope).count
  end

  test "a remaining owner can manage an open subscription after another owner deletes their account" do
    signed_member(role: "owner")
    Subscription.for(@scope).create!(status: "active", livemode: true)
    delete "/api/v1/settings/account", headers: bearer(@owner_token)
    assert_response :no_content
    assert Organization.exists?(@organization.id)
    assert_equal 1, Membership.for(@scope).count
  end

  test "a regular member can delete their account without transferring ownership" do
    user, token, = signed_member
    get "/api/v1/settings/account", headers: bearer(token)
    assert_response :ok
    assert_nil data.fetch("blocker")
    delete "/api/v1/settings/account", headers: bearer(token)
    assert_response :no_content
    refute User.exists?(user.id)
    assert User.exists?(@owner.id)
    assert_equal [ @owner.id ], Membership.for(@scope).pluck(:user_id)
  end

  test "deletion checks every joined organization and rechecks a blocker introduced after preview" do
    post "/api/v1/organizations", params: { name: "Second workspace" }, headers: bearer(@owner_token), as: :json
    assert_response :created
    second_scope = Session.scope_for(@scope.session.reload)
    put "/api/v1/current-organization", params: { organizationId: @organization.id }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    get "/api/v1/settings/account", headers: bearer(@owner_token)
    assert_nil data.fetch("blocker")
    Membership.for(second_scope).create!(user: create_user, role: "member", access: "viewer")
    delete "/api/v1/settings/account", headers: bearer(@owner_token)
    assert_error :conflict, "transfer_ownership"
    assert_equal "Second workspace", response.parsed_body.dig("error", "details", "organization")
    assert User.exists?(@owner.id)
    assert Organization.exists?(@organization.id)
    assert_equal 1, Membership.for(@scope).count
  end
end
