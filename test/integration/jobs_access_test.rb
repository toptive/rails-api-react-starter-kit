require "test_helper"
require_relative "../support/admin_requests"

class JobsAccessTest < ActionDispatch::IntegrationTest
  include AdminRequests

  test "ticket handoff sets a five minute dashboard cookie and redirects to Mission Control" do
    path = issue_access
    get path
    assert_response :found
    assert_redirected_to "/jobs"
    cookie = response.headers.fetch("Set-Cookie")
    assert_includes cookie, "path=/jobs"
    assert_includes cookie, "max-age=300"
    assert_includes cookie.downcase, "httponly"
    assert_includes cookie.downcase, "samesite=strict"
    I18n.backend.reload!
    get "/jobs"
    follow_redirect! while response.redirect?
    assert_response :ok
    assert_includes response.body, "Mission control"
    get "/api/v1/bootstrap?locale=es"
    assert_equal "es", data.fetch("locale")
    assert I18n.exists?("errors.api.unauthorized", :es)
    travel 6.minutes do
      get "/jobs"
      assert_response :not_found
    end
  end

  test "ticket is single use and expiry tampering or absence are refused" do
    path = issue_access
    get path
    assert_response :found
    get path
    assert_error :not_found, "not_found"
    assert_nil response.headers["Set-Cookie"]
    expired_path = issue_access
    travel 61.seconds do
      get expired_path
      assert_error :not_found, "not_found"
      assert_nil response.headers["Set-Cookie"]
    end
    [ "/jobs/session", "#{issue_access}tampered", "/jobs/session?ticket=unknown" ].each do |invalid_path|
      get invalid_path
      assert_error :not_found, "not_found"
    end
  end

  test "demotion or revocation prevents exchanging an issued ticket" do
    path = issue_access
    @admin.update!(role: "user")
    get path
    assert_error :not_found, "not_found"
    @admin.update!(role: "superadmin")
    path = issue_access
    delete "/api/v1/auth/session", headers: admin_headers
    get path
    assert_error :not_found, "not_found"
  end

  test "dashboard cookies are rejected after tampering revocation or demotion" do
    get issue_access
    cookie = response.headers.fetch("Set-Cookie").split(";", 2).first
    get "/jobs", headers: { "Cookie" => cookie.sub(/.$/, "x") }
    assert_response :not_found
    @admin.update!(role: "user")
    get "/jobs", headers: { "Cookie" => cookie }
    assert_response :not_found
    @admin.update!(role: "superadmin")
    delete "/api/v1/auth/session", headers: admin_headers
    get "/jobs", headers: { "Cookie" => cookie }
    assert_response :not_found
  end

  test "bearer authentication alone never grants browser dashboard access" do
    get "/jobs", headers: admin_headers
    assert_response :not_found
  end

  private

  def issue_access
    post "/api/v1/admin/jobs-access", headers: admin_headers, as: :json
    assert_response :created
    assert_nil response.headers["Set-Cookie"]
    uri = URI(data.fetch("url"))
    assert_equal Rails.application.config.x.api_origin, "#{uri.scheme}://#{uri.host}:#{uri.port}"
    assert_equal "/jobs/session", uri.path
    assert URI.decode_www_form(uri.query).to_h.fetch("ticket")
    event = AuditEvent.where(action: "admin.jobs_dashboard_opened").order(:created_at).last
    assert_equal @admin.id, event.actor_id
    assert_equal "127.0.0.1", event.ip_address
    uri.request_uri
  end
end
