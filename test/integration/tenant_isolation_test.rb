require "test_helper"
require_relative "../support/tenancy_requests"

class TenantIsolationTest < ActionDispatch::IntegrationTest
  include TenancyRequests

  test "Membership tenant isolation prevents reading updating or deleting another organization's rows" do
    other = create_user(name: "Other owner")
    other_token = sign_in(other)
    other_scope = Session.scope_for(Session.find_by_token(other_token))
    secret_member = seat(create_user, scope: other_scope)
    get "/api/v1/settings/members", headers: bearer(@owner_token)
    assert_response :ok
    assert_equal [ @scope.membership.id ], data.pluck("id")
    refute_includes response.body, secret_member.user.email
    put "/api/v1/settings/members/#{secret_member.id}", params: { role: "admin", organizationId: other_scope.organization.id }, headers: bearer(@owner_token), as: :json
    assert_error :not_found, "not_found"
    delete "/api/v1/settings/members/#{secret_member.id}", headers: bearer(@owner_token)
    assert_error :not_found, "not_found"
    assert_equal "member", Membership.for(other_scope).find(secret_member.id).role
    assert_equal 2, Membership.for(other_scope).count
  end

  test "Invitation tenant isolation prevents listing revoking or creating rows under another organization" do
    other_token = sign_in(create_user(name: "Other owner"))
    other_scope = Session.scope_for(Session.find_by_token(other_token))
    secret_id, raw = invite("secret@example.com", headers: bearer(other_token))
    get "/api/v1/settings/invitations", headers: bearer(@owner_token)
    assert_response :ok
    assert_empty data
    delete "/api/v1/settings/invitations/#{secret_id}", headers: bearer(@owner_token)
    assert_error :not_found, "not_found"
    assert Invitation.for(other_scope).exists?(secret_id)
    post "/api/v1/settings/invitations", params: { email: "ours@example.com", organizationId: other_scope.organization.id }, headers: bearer(@owner_token), as: :json
    assert_response :created
    assert Invitation.for(@scope).exists?(data.fetch("id"))
    refute Invitation.for(other_scope).exists?(data.fetch("id"))
    # Possession of the public link allows preview; it does not authorize membership.
    post "/api/v1/invitations/#{raw}/acceptance", headers: bearer(@owner_token), as: :json
    assert_error :conflict, "email_mismatch"
    assert_nil Invitation.for(other_scope).find(secret_id).accepted_at
    refute Membership.for(other_scope).exists?(user_id: @owner.id)
  end

  test "BillingSubscription tenant isolation keeps another organization's billing out of account deletion" do
    other_token = sign_in(create_user)
    other_scope = Session.scope_for(Session.find_by_token(other_token))
    subscription = BillingSubscription.for(other_scope).create!(plan: "pro", stripe_customer_id: "cus_test", stripe_subscription_id: "sub_" + SecureRandom.hex(8), status: "active", livemode: true)
    get "/api/v1/settings/account", params: { organizationId: other_scope.organization.id }, headers: bearer(@owner_token)
    assert_response :ok
    assert_nil data.fetch("blocker")
    delete "/api/v1/settings/account", params: { organizationId: other_scope.organization.id }, headers: bearer(@owner_token), as: :json
    assert_response :no_content
    assert BillingSubscription.for(other_scope).exists?(subscription.id)
    assert Organization.exists?(other_scope.organization.id)
    assert Membership.for(other_scope).exists?(user_id: other_scope.user.id)
    get "/api/v1/settings/account", headers: bearer(other_token)
    assert_equal "subscription_active", data.dig("blocker", "reason")
  end

  test "BillingSubscription tenant isolation keeps overview checkout and portal in the caller organization" do
    saved = ENV.to_h.slice("BILLING_ENABLED", "BILLING_MODE")
    ENV["BILLING_ENABLED"] = "true"
    ENV["BILLING_MODE"] = "test"
    other_token = sign_in(create_user)
    other_scope = Session.scope_for(Session.find_by_token(other_token))
    BillingSubscription.for(other_scope).create!(plan: "pro", status: "active", livemode: false,
      stripe_customer_id: "cus_secret", stripe_subscription_id: "sub_secret", current_period_end: 1.day.from_now)
    get "/api/v1/settings/billing", params: { organizationId: other_scope.organization.id }, headers: bearer(@owner_token)
    assert_response :ok
    assert_equal "free", data.fetch("plan")
    assert_nil data.fetch("subscription")
    post "/api/v1/settings/billing/portal-session", params: { organizationId: other_scope.organization.id }, headers: bearer(@owner_token), as: :json
    assert_error :conflict, "no_subscription"
    refute_includes response.body, "cus_secret"
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  test "organization settings and switching never accept a supplied organization as authority" do
    other_token = sign_in(create_user(name: "Private team"))
    other_org = Session.scope_for(Session.find_by_token(other_token)).organization
    get "/api/v1/settings/organization", params: { organizationId: other_org.id }, headers: bearer(@owner_token)
    assert_response :ok
    assert_equal @organization.id, data.dig("organization", "id")
    put "/api/v1/settings/organization", params: { organizationId: other_org.id, name: "Ours" }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal "Private team", other_org.reload.name
    put "/api/v1/current-organization", params: { organizationId: other_org.id }, headers: bearer(@owner_token), as: :json
    assert_error :conflict, "not_member"
    get "/api/v1/bootstrap", headers: bearer(@owner_token)
    assert_equal [ @organization.id ], data.dig("auth", "organizations").pluck("id")
  end
end
