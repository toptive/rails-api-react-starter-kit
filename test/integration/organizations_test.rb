require "test_helper"
require_relative "../support/tenancy_requests"

class OrganizationsTest < ActionDispatch::IntegrationTest
  include TenancyRequests

  test "new sessions and bootstrap have real organization and membership records" do
    assert_equal @organization.id, @scope.session.organization_id
    assert_equal @organization.id, @owner.reload.last_organization_id
    assert @organization.personal?
    assert_nil @organization.onboarded_at
    get "/api/v1/bootstrap", headers: bearer(@owner_token)
    assert_response :ok
    assert_equal @organization.id, data.dig("auth", "organization", "id")
    assert_equal @scope.membership.id, data.dig("auth", "membership", "id")
    assert_equal "owner", data.dig("auth", "membership", "role")
    assert_equal "full", data.dig("auth", "membership", "access")
    assert_nil data.dig("auth", "membership", "user")
    assert_equal [ @organization.id ], data.dig("auth", "organizations").pluck("id")
    assert_equal true, data.dig("auth", "onboardingRequired")
  end

  test "create organization switches this device atomically and starts onboarded" do
    other_device = Session.find_by_token(sign_in(@owner))
    assert_difference "Organization.count", 1 do
      post "/api/v1/organizations", params: { name: " Team ", personal: true, role: "member" }, headers: bearer(@owner_token), as: :json
    end
    assert_response :created
    org = Organization.find(data.fetch("id"))
    assert_equal "Team", data.fetch("name")
    assert_equal false, data.fetch("personal")
    assert_match(/\Ateam-/, data.fetch("slug"))
    assert org.onboarded_at
    assert_equal org.id, @scope.session.reload.organization_id
    assert_equal org.id, @owner.reload.last_organization_id
    assert_equal @organization.id, other_device.reload.organization_id
    get "/api/v1/bootstrap", headers: bearer(@owner_token)
    assert_equal "owner", data.dig("auth", "membership", "role")
    assert_equal false, data.dig("auth", "onboardingRequired")
    assert_equal [ @organization.id, org.id ], data.dig("auth", "organizations").pluck("id")
    event = AuditEvent.find_by!(action: "organization.created", subject_id: org.id)
    assert_equal org.id, event.organization_id
    assert_equal @owner.id, event.actor_id
  end

  test "create and rename reject invalid names and preserve the session and organization" do
    [ "", "a", "a" * 81 ].each do |name|
      assert_no_difference "Organization.count" do
        post "/api/v1/organizations", params: { name: name }, headers: bearer(@owner_token), as: :json
      end
      assert_error :unprocessable_entity, "validation_failed"
      put "/api/v1/settings/organization", params: { name: name }, headers: bearer(@owner_token), as: :json
      assert_error :unprocessable_entity, "validation_failed"
      assert_equal "Owner", @organization.reload.name
      assert_equal @organization.id, @scope.session.reload.organization_id
    end
    post "/api/v1/organizations", params: { name: "a" }, headers: bearer(@owner_token), as: :json
    assert_field_error "name", "validation.length_min", bindings: { "count" => 2 }
    put "/api/v1/settings/organization", params: { name: "a" * 81 }, headers: bearer(@owner_token), as: :json
    assert_field_error "name", "validation.length_max", bindings: { "count" => 80 }
    post "/api/v1/organizations", params: {}, headers: bearer(@owner_token), as: :json
    assert_error :bad_request, "bad_request"
    put "/api/v1/settings/organization", params: {}, headers: bearer(@owner_token), as: :json
    assert_error :bad_request, "bad_request"
    post "/api/v1/organizations", params: { name: 42 }, headers: bearer(@owner_token), as: :json
    assert_error :bad_request, "bad_request"
    put "/api/v1/settings/organization", params: { name: [] }, headers: bearer(@owner_token), as: :json
    assert_error :bad_request, "bad_request"
  end

  test "switch remembers the choice per device and new sessions use the last organization" do
    other_device = Session.find_by_token(sign_in(@owner))
    post "/api/v1/organizations", params: { name: "Team" }, headers: bearer(@owner_token), as: :json
    org_id = data.fetch("id")
    put "/api/v1/current-organization", params: { organizationId: @organization.id }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal @organization.id, data.dig("organization", "id")
    assert_equal "owner", data.dig("membership", "role")
    assert_nil data.dig("membership", "user")
    put "/api/v1/current-organization", params: { organizationId: org_id }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal org_id, @owner.reload.last_organization_id
    assert_equal @organization.id, other_device.reload.organization_id
    new_device = Session.find_by_token(sign_in(@owner))
    assert_equal org_id, new_device.organization_id
  end

  test "switch refuses nonmembership and malformed organization ids without changing either preference" do
    [ SecureRandom.uuid, "bad-id" ].each do |id|
      put "/api/v1/current-organization", params: { organizationId: id }, headers: bearer(@owner_token), as: :json
      assert_error :conflict, "not_member"
      assert_equal @organization.id, @scope.session.reload.organization_id
      assert_equal @organization.id, @owner.reload.last_organization_id
    end
    [ {}, { organizationId: true } ].each do |attributes|
      put "/api/v1/current-organization", params: attributes, headers: bearer(@owner_token), as: :json
      assert_error :bad_request, "bad_request"
    end
  end

  test "a removed membership falls back to a valid organization on the next request" do
    _, token, membership = signed_member
    old_device = Session.find_by_token(token)
    delete "/api/v1/settings/members/#{membership.id}", headers: bearer(@owner_token)
    assert_response :no_content
    get "/api/v1/bootstrap", headers: bearer(token)
    assert_response :ok
    refute_equal @organization.id, data.dig("auth", "organization", "id")
    assert_equal true, data.dig("auth", "organization", "personal")
    assert_equal "owner", data.dig("auth", "membership", "role")
    assert_equal data.dig("auth", "organization", "id"), old_device.reload.organization_id
  end

  test "single mode shares the default organization gives only its first user ownership and refuses creation" do
    Rails.application.config.x.tenancy = "single"
    first, second = Array.new(2) { create_user }
    first_token = sign_in(first)
    second_token = sign_in(second)
    shared = Organization.find_by!(slug: "default")
    [ [ first_token, "owner", true ], [ second_token, "member", false ] ].each do |token, role, required|
      get "/api/v1/bootstrap", headers: bearer(token)
      assert_response :ok
      assert_equal "single", data.dig("app", "tenancy")
      assert_equal shared.id, data.dig("auth", "organization", "id")
      assert_equal role, data.dig("auth", "membership", "role")
      assert_equal required, data.dig("auth", "onboardingRequired")
      assert_equal 1, data.dig("auth", "organizations").length
      assert_no_difference "Organization.count" do
        post "/api/v1/organizations", params: { name: "Team" }, headers: bearer(token), as: :json
      end
      assert_error :forbidden, "forbidden"
    end
    assert_equal shared.id, Organization.ensure_default!.id
  end

  test "organization settings read and rename through their serializers and audit" do
    get "/api/v1/settings/organization", headers: bearer(@owner_token)
    assert_response :ok
    assert_equal @organization.id, data.dig("organization", "id")
    assert_equal true, data.fetch("canEdit")
    put "/api/v1/settings/organization", params: { name: " Renamed ", slug: "ignored" }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal "Renamed", data.fetch("name")
    assert_equal @organization.slug, data.fetch("slug")
    assert AuditEvent.exists?(action: "organization.updated", subject_id: @organization.id, organization_id: @organization.id)
    get "/api/v1/bootstrap", headers: bearer(@owner_token)
    assert_equal "Renamed", data.dig("auth", "organizations", 0, "name")
  end

  test "onboarding can be read renamed or skipped and records completion" do
    get "/api/v1/onboarding", headers: bearer(@owner_token)
    assert_response :ok
    assert_equal({ "organizationName" => "Owner", "required" => true }, data)
    put "/api/v1/onboarding", params: { name: "a" }, headers: bearer(@owner_token), as: :json
    assert_field_error "name", "validation.length_min", bindings: { "count" => 2 }
    assert_nil @organization.reload.onboarded_at
    put "/api/v1/onboarding", params: { name: {} }, headers: bearer(@owner_token), as: :json
    assert_error :bad_request, "bad_request"
    put "/api/v1/onboarding", params: { name: " Team " }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal "Team", data.fetch("name")
    assert @organization.reload.onboarded_at
    assert AuditEvent.exists?(action: "organization.onboarded", subject_id: @organization.id)
    get "/api/v1/onboarding", headers: bearer(@owner_token)
    assert_equal false, data.fetch("required")
    get "/api/v1/bootstrap", headers: bearer(@owner_token)
    assert_equal false, data.dig("auth", "onboardingRequired")
    [ {}, { name: "   " } ].each do |attributes|
      put "/api/v1/onboarding", params: attributes, headers: bearer(@owner_token), as: :json
      assert_response :ok
      assert_equal "Team", data.fetch("name")
    end
  end

  test "impersonation does not enter onboarding even when the target is an owner" do
    admin = create_user(role: "superadmin")
    admin_session = Session.find_by_token(sign_in(admin))
    raw = SecureRandom.urlsafe_base64(32)
    Session.create!(user: @owner, organization: @organization, impersonator_user: admin,
      impersonator_session: admin_session, token_hash: Digest::SHA256.digest(raw),
      expires_at: 8.hours.from_now, authenticated_at: Time.current)
    get "/api/v1/bootstrap", headers: bearer(raw)
    assert_equal false, data.dig("auth", "onboardingRequired")
    get "/api/v1/onboarding", headers: bearer(raw)
    assert_error :forbidden, "forbidden"
    put "/api/v1/onboarding", params: {}, headers: bearer(raw), as: :json
    assert_error :forbidden, "forbidden"
  end
end
