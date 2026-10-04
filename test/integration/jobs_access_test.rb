require "test_helper"
require_relative "../support/auth_requests"

class JobsAccessTest < ActionDispatch::IntegrationTest
  include AuthRequests

  test "browser access needs a short lived signed cookie from a live superadmin session" do
    token = sign_in(create_user(role: "superadmin"))
    post "/api/v1/admin/jobs-access", headers: bearer(token), as: :json
    assert_response :no_content
    cookie = response.headers.fetch("Set-Cookie")
    assert_includes cookie, "path=/jobs"
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

  test "missing ordinary and impersonating sessions cannot mint dashboard access" do
    post "/api/v1/admin/jobs-access", as: :json
    assert_error :not_found, "not_found"
    token = sign_in(create_user)
    post "/api/v1/admin/jobs-access", headers: bearer(token), as: :json
    assert_error :not_found, "not_found"
    assert_nil response.headers["Set-Cookie"]
    user = create_user(role: "superadmin")
    issued = Session.create_for(user, ActionDispatch::Request.new(Rack::MockRequest.env_for("/")))
    issued[:session].update!(impersonator_user: create_user(role: "superadmin"), sudo_until: nil)
    post "/api/v1/admin/jobs-access", headers: bearer(issued[:token]), as: :json
    assert_error :not_found, "not_found"
  end

  test "tampering revocation and demotion remove browser access immediately" do
    token = sign_in(create_user(role: "superadmin"))
    post "/api/v1/admin/jobs-access", headers: bearer(token), as: :json
    cookie = response.headers.fetch("Set-Cookie").split(";", 2).first
    get "/jobs", headers: { "Cookie" => cookie.sub(/.$/, "x") }
    assert_response :not_found
    Session.find_by_token(token).user.update!(role: "user")
    get "/jobs", headers: { "Cookie" => cookie }
    assert_response :not_found
    Session.find_by_token(token).user.update!(role: "superadmin")
    delete "/api/v1/auth/session", headers: bearer(token)
    get "/jobs", headers: { "Cookie" => cookie }
    assert_response :not_found
  end
end
