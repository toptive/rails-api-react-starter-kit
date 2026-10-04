require "test_helper"
require_relative "../support/admin_requests"

class AdminOrganizationsTest < ActionDispatch::IntegrationTest
  include AdminRequests

  test "organization index searches names literally and includes member counts with pagination" do
    target = create_user
    first = Organization.create_owned!(target, name: "Search% first")
    second = Organization.create_owned!(create_user, name: "Search% second")
    Organization.create_owned!(create_user, name: "Search different")
    tenant = Session::Scope.new(organization: second)
    Membership.for(tenant).create!(user: target, role: "member", access: "viewer")
    get "/api/v1/admin/organizations", params: { q: "SEARCH%", perPage: 1 }, headers: admin_headers
    assert_response :ok
    assert_equal second.id, data.first.fetch("id")
    assert_equal 2, data.first.fetch("members")
    assert data.first.fetch("insertedAt").end_with?("Z")
    assert_equal 2, response.parsed_body.dig("meta", "pagination", "total")
    get "/api/v1/admin/organizations", params: { q: "SEARCH%", perPage: 1, page: 2 }, headers: admin_headers
    assert_equal first.id, data.first.fetch("id")
    get "/api/v1/admin/organizations", params: { q: "absent" }, headers: admin_headers
    assert_empty data
  end

  test "organization detail only returns that organization's memberships with users" do
    owner = create_user
    organization = Organization.create_owned!(owner, name: "Other tenant")
    other = Organization.create_owned!(create_user, name: "Separate tenant")
    member = create_user
    Membership.for(Session::Scope.new(organization: organization)).create!(user: member, role: "member", access: "viewer")
    get "/api/v1/admin/organizations/#{organization.id}", headers: admin_headers
    assert_response :ok
    assert_equal organization.id, data.dig("organization", "id")
    assert_equal [ owner.id, member.id ], data.fetch("memberships").map { |row| row.dig("user", "id") }
    refute data.fetch("memberships").any? { |row| row.dig("user", "id") == Membership.for(Session::Scope.new(organization: other)).first.user_id }
    get "/api/v1/admin/organizations/#{SecureRandom.uuid}", headers: admin_headers
    assert_error :not_found, "not_found"
  end
end
