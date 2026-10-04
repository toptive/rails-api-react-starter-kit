require "test_helper"
require_relative "../support/tenancy_requests"

class TenancyAuthorizationTest < ActionDispatch::IntegrationTest
  include TenancyRequests

  test "every protected tenancy endpoint rejects anonymous callers" do
    [ [ :put, "/current-organization" ], [ :post, "/organizations" ], [ :get, "/onboarding" ], [ :put, "/onboarding" ],
      [ :post, "/invitations/missing/acceptance" ], [ :get, "/settings/organization" ], [ :put, "/settings/organization" ],
      [ :get, "/settings/members" ], [ :put, "/settings/members/#{@scope.membership.id}" ],
      [ :delete, "/settings/members/#{@scope.membership.id}" ], [ :get, "/settings/invitations" ],
      [ :post, "/settings/invitations" ], [ :delete, "/settings/invitations/#{SecureRandom.uuid}" ] ].each do |method, path|
      public_send method, "/api/v1#{path}", as: :json
      assert_response :unauthorized, "#{method.upcase} #{path}"
      assert_error :unauthorized, "unauthorized"
    end
  end

  test "each role and access combination can read members but only full owners and admins manage" do
    [ "owner", "admin", "member" ].product(%w[full viewer]).each do |role, access|
      _, token, = signed_member(role: role, access: access)
      manager = role.in?(%w[owner admin]) && access == "full"
      get "/api/v1/settings/organization", headers: bearer(token)
      assert_response :ok
      assert_equal manager, data.fetch("canEdit")
      get "/api/v1/settings/members", headers: bearer(token)
      assert_response :ok
      assert_includes data.pluck("id"), @scope.membership.id
      get "/api/v1/bootstrap", headers: bearer(token)
      assert_equal manager, data.dig("auth", "onboardingRequired")
      get "/api/v1/onboarding", headers: bearer(token)
      manager ? assert_response(:ok) : assert_error(:forbidden, "forbidden")
      get "/api/v1/settings/invitations", headers: bearer(token)
      manager ? assert_response(:ok) : assert_error(:forbidden, "forbidden")
      put "/api/v1/settings/organization", params: { name: "Team" }, headers: bearer(token), as: :json
      manager ? assert_response(:ok) : assert_error(:forbidden, "forbidden")
      put "/api/v1/onboarding", params: {}, headers: bearer(token), as: :json
      manager ? assert_response(:ok) : assert_error(:forbidden, "forbidden")
      @organization.reload.update!(onboarded_at: nil)
      target = seat(create_user)
      put "/api/v1/settings/members/#{target.id}", params: { role: "admin" }, headers: bearer(token), as: :json
      manager ? assert_response(:ok) : assert_error(:forbidden, "forbidden")
      delete "/api/v1/settings/members/#{target.id}", headers: bearer(token)
      manager ? assert_response(:no_content) : assert_error(:forbidden, "forbidden")
      post "/api/v1/settings/invitations", params: { email: "#{SecureRandom.hex(6)}@example.com" }, headers: bearer(token), as: :json
      if manager
        assert_response :created
        invitation_id = data.fetch("id")
      else
        assert_error :forbidden, "forbidden"
        invitation_id, = invite("#{SecureRandom.hex(6)}@example.com")
      end
      delete "/api/v1/settings/invitations/#{invitation_id}", headers: bearer(token)
      manager ? assert_response(:no_content) : assert_error(:forbidden, "forbidden")
    end
  end

  test "member and viewer can leave their own seat but cannot remove someone else" do
    [ [ "member", "full" ], [ "member", "viewer" ], [ "admin", "viewer" ], [ "owner", "viewer" ] ].each do |role, access|
      _, token, membership = signed_member(role: role, access: access)
      delete "/api/v1/settings/members/#{@scope.membership.id}", headers: bearer(token)
      assert_error :forbidden, "forbidden"
      delete "/api/v1/settings/members/#{membership.id}", headers: bearer(token)
      assert_response :no_content
      refute Membership.for(@scope).exists?(id: membership.id)
      get "/api/v1/bootstrap", headers: bearer(token)
      refute_equal @organization.id, data.dig("auth", "organization", "id")
    end
  end
end
