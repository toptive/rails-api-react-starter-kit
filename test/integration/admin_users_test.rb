require "test_helper"
require_relative "../support/admin_requests"

class AdminUsersTest < ActionDispatch::IntegrationTest
  include AdminRequests

  test "dashboard reports global counts and advertises the jobs dashboard" do
    create_user
    get "/api/v1/admin/dashboard", headers: admin_headers
    assert_response :ok
    assert_equal({ "users" => User.count, "organizations" => Organization.count }, data)
    get "/api/v1/bootstrap"
    assert_equal true, data.dig("app", "jobsDashboard")
  end

  test "user index searches name or email literally case insensitively and paginates newest first" do
    first = create_user(name: "Search% Person", email: "first@example.com")
    second = create_user(name: "Search% Person", email: "second@example.com")
    create_user(name: "Search Someone", email: "third@example.com")
    get "/api/v1/admin/users", params: { q: " SEARCH% ", perPage: 1 }, headers: admin_headers
    assert_response :ok
    assert_equal [ second.id ], data.map { |row| row.fetch("id") }
    assert_equal({ "page" => 1, "perPage" => 1, "total" => 2, "totalPages" => 2 }, response.parsed_body.dig("meta", "pagination"))
    get "/api/v1/admin/users", params: { q: "SEARCH%", perPage: 1, page: 2 }, headers: admin_headers
    assert_equal [ first.id ], data.map { |row| row.fetch("id") }
    get "/api/v1/admin/users", params: { q: "SECOND@EXAMPLE" }, headers: admin_headers
    assert_equal [ second.id ], data.map { |row| row.fetch("id") }
    get "/api/v1/admin/users", params: { q: "absent" }, headers: admin_headers
    assert_empty data
  end

  test "user detail includes the user's organizations across tenants" do
    target = create_user
    organization = Organization.create_owned!(target, name: "Target workspace")
    get "/api/v1/admin/users/#{target.id}", headers: admin_headers
    assert_response :ok
    assert_equal target.id, data.dig("user", "id")
    assert_equal [ organization.id ], data.fetch("organizations").map { |row| row.fetch("id") }
    get "/api/v1/admin/users/#{SecureRandom.uuid}", headers: admin_headers
    assert_error :not_found, "not_found"
  end

  test "changing a global role records from and to and is idempotent" do
    target = create_user
    put "/api/v1/admin/users/#{target.id}", params: { role: "superadmin" }, headers: admin_headers, as: :json
    assert_response :ok
    assert_equal "superadmin", data.fetch("role")
    event = AuditEvent.find_by!(action: "user.role_changed", subject_id: target.id)
    assert_equal @admin.id, event.actor_id
    assert_equal({ "from" => "user", "to" => "superadmin" }, event.metadata)
    assert_equal "127.0.0.1", event.ip_address
    assert_no_difference "AuditEvent.count" do
      put "/api/v1/admin/users/#{target.id}", params: { role: "superadmin" }, headers: admin_headers, as: :json
      assert_response :ok
    end
    put "/api/v1/admin/users/#{target.id}", params: { role: "user" }, headers: admin_headers, as: :json
    assert_response :ok
    assert_equal "user", target.reload.role
  end

  test "role updates reject missing wrong typed and unknown roles without writes" do
    target = create_user
    [ {}, { role: 2 }, { role: nil } ].each do |attributes|
      assert_no_difference "AuditEvent.count" do
        put "/api/v1/admin/users/#{target.id}", params: attributes, headers: admin_headers, as: :json
      end
      assert_error :bad_request, "bad_request"
    end
    put "/api/v1/admin/users/#{target.id}", params: { role: "owner" }, headers: admin_headers, as: :json
    assert_admin_field "role", "validation.inclusion"
    assert_equal "user", target.reload.role
    put "/api/v1/admin/users/#{SecureRandom.uuid}", params: { role: "user" }, headers: admin_headers, as: :json
    assert_error :not_found, "not_found"
  end
end
