require "test_helper"
require_relative "../support/tenancy_requests"

class MembershipsTest < ActionDispatch::IntegrationTest
  include TenancyRequests

  test "create organization invite accept list change role and remove flow" do
    post "/api/v1/organizations", params: { name: "Together" }, headers: bearer(@owner_token), as: :json
    assert_response :created
    organization_id = data.fetch("id")
    guest = create_user(name: "Guest")
    guest_token = sign_in(guest)
    personal_id = Session.find_by_token(guest_token).organization_id
    invitation_id, raw = invite(guest.email, role: "admin", access: "viewer")
    get "/api/v1/invitations/#{raw}", headers: bearer(guest_token)
    assert_response :ok
    assert_equal true, data.fetch("emailMatches")
    post "/api/v1/invitations/#{raw}/acceptance", headers: bearer(guest_token), as: :json
    assert_response :created
    member_id = data.fetch("id")
    assert_equal guest.id, data.dig("user", "id")
    assert_equal "admin", data.fetch("role")
    assert_equal "viewer", data.fetch("access")
    assert_equal organization_id, guest.reload.last_organization_id
    assert_equal organization_id, Session.find_by_token(guest_token).organization_id
    get "/api/v1/settings/members", headers: bearer(@owner_token)
    assert_response :ok
    assert_equal [ @owner.id, guest.id ], data.map { |member| member.dig("user", "id") }
    assert data.all? { |member| member.fetch("insertedAt").match?(/Z\z/) }
    put "/api/v1/settings/members/#{member_id}", params: { role: "member", access: "full" }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal "member", data.fetch("role")
    assert_equal "full", data.fetch("access")
    delete "/api/v1/settings/members/#{member_id}", headers: bearer(@owner_token)
    assert_response :no_content
    get "/api/v1/settings/members", headers: bearer(@owner_token)
    assert_equal [ @owner.id ], data.map { |member| member.dig("user", "id") }
    get "/api/v1/bootstrap", headers: bearer(guest_token)
    assert_equal personal_id, data.dig("auth", "organization", "id")
    [ [ "invitation.created", invitation_id ], [ "invitation.accepted", invitation_id ],
      [ "membership.updated", member_id ], [ "membership.deleted", member_id ], [ "organization.member_removed", member_id ] ].each do |action, subject_id|
      assert AuditEvent.exists?(action: action, subject_id: subject_id, organization_id: organization_id)
    end
  end

  test "last owner cannot leave then promotes another owner and leaves successfully" do
    _, colleague_token, colleague = signed_member
    assert_no_difference "Membership.for(@scope).count" do
      delete "/api/v1/settings/members/#{@scope.membership.id}", headers: bearer(@owner_token)
    end
    assert_error :conflict, "last_owner"
    assert_equal @organization.id, @scope.session.reload.organization_id
    assert_no_difference "AuditEvent.where(action: 'membership.deleted').count" do
      put "/api/v1/settings/members/#{@scope.membership.id}", params: { role: "admin" }, headers: bearer(@owner_token), as: :json
    end
    assert_field_error "role", "validation.last_owner"
    put "/api/v1/settings/members/#{colleague.id}", params: { role: "owner" }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal "owner", data.fetch("role")
    delete "/api/v1/settings/members/#{@scope.membership.id}", headers: bearer(@owner_token)
    assert_response :no_content
    assert_empty response.body
    get "/api/v1/bootstrap", headers: bearer(@owner_token)
    assert_response :ok
    refute_equal @organization.id, data.dig("auth", "organization", "id")
    assert_equal true, data.dig("auth", "organization", "personal")
    assert_equal "owner", data.dig("auth", "membership", "role")
    get "/api/v1/settings/members", headers: bearer(colleague_token)
    assert_equal [ colleague.id ], data.pluck("id")
    delete "/api/v1/settings/members/#{colleague.id}", headers: bearer(colleague_token)
    assert_error :conflict, "last_owner"
  end

  test "leaving resets the device to another existing membership" do
    post "/api/v1/organizations", params: { name: "Second team" }, headers: bearer(@owner_token), as: :json
    second_org = Organization.find(data.fetch("id"))
    second_scope = Session.scope_for(@scope.session.reload)
    seat(create_user, role: "owner", scope: second_scope)
    delete "/api/v1/settings/members/#{second_scope.membership.id}", headers: bearer(@owner_token)
    assert_response :no_content
    assert_equal @organization.id, @scope.session.reload.organization_id
    assert_equal @organization.id, @owner.reload.last_organization_id
    refute Membership.for(second_scope).exists?(user_id: @owner.id)
    assert Organization.exists?(second_org.id)
  end

  test "only owners can promote owners or change owners and admins cannot remove an owner" do
    _, admin_token, = signed_member(role: "admin")
    target = seat(create_user)
    [ [ target.id, { role: "owner" } ], [ @scope.membership.id, { role: "member" } ],
      [ @scope.membership.id, { access: "viewer" } ] ].each do |id, attributes|
      put "/api/v1/settings/members/#{id}", params: attributes, headers: bearer(admin_token), as: :json
      assert_field_error "role", "validation.owner_only"
    end
    delete "/api/v1/settings/members/#{@scope.membership.id}", headers: bearer(admin_token)
    assert_error :forbidden, "forbidden"
    assert_equal "owner", @scope.membership.reload.role
    assert_equal "full", @scope.membership.access
    put "/api/v1/settings/members/#{target.id}", params: { role: "admin", access: "viewer" }, headers: bearer(admin_token), as: :json
    assert_response :ok
    assert_equal "admin", data.fetch("role")
    assert_equal "viewer", data.fetch("access")
  end

  test "an owner can demote and remove another owner while one remains" do
    _, _, colleague = signed_member(role: "owner")
    put "/api/v1/settings/members/#{colleague.id}", params: { role: "admin" }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    assert_equal "admin", data.fetch("role")
    put "/api/v1/settings/members/#{colleague.id}", params: { role: "owner" }, headers: bearer(@owner_token), as: :json
    assert_response :ok
    delete "/api/v1/settings/members/#{colleague.id}", headers: bearer(@owner_token)
    assert_response :no_content
  end

  test "membership enums validate and unknown ids return not found" do
    target = seat(create_user)
    [ [ { role: "OWNER" }, "role" ], [ { access: "invalid" }, "access" ] ].each do |attributes, field|
      put "/api/v1/settings/members/#{target.id}", params: attributes, headers: bearer(@owner_token), as: :json
      assert_field_error field, "validation.inclusion"
    end
    [ "not-a-uuid", SecureRandom.uuid ].each do |id|
      put "/api/v1/settings/members/#{id}", params: { role: "admin" }, headers: bearer(@owner_token), as: :json
      assert_error :not_found, "not_found"
      delete "/api/v1/settings/members/#{id}", headers: bearer(@owner_token)
      assert_error :not_found, "not_found"
    end
    put "/api/v1/settings/members/#{target.id}", params: { role: 42 }, headers: bearer(@owner_token), as: :json
    assert_error :bad_request, "bad_request"
  end
end
