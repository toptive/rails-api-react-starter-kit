require "test_helper"

class HealthTest < ActionDispatch::IntegrationTest
  test "Rails probe and versioned health work without a session" do
    get "/up"
    assert_response :ok
    get "/api/v1/health", headers: { "Authorization" => "Bearer arbitrary-token" }
    assert_response :ok
    assert_equal({ "data" => { "status" => "ok" }, "meta" => {} }, response.parsed_body)
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Set-Cookie"]
  end

  test "job dashboard is inaccessible without a verified superadmin session" do
    get "/admin/jobs"
    assert_response :not_found
    get "/admin/jobs", headers: { "Authorization" => "Bearer arbitrary-token" }
    assert_response :not_found
  end

  test "CORS permits the SPA origin and refuses an unknown origin" do
    headers = { "Origin" => "http://localhost:5173", "Access-Control-Request-Method" => "GET",
      "Access-Control-Request-Headers" => "Authorization,Accept-Language" }
    options "/api/v1/health", headers: headers
    assert_equal "http://localhost:5173", response.headers["Access-Control-Allow-Origin"]
    assert_nil response.headers["Access-Control-Allow-Credentials"]
    options "/api/v1/health", headers: headers.merge("Origin" => "https://untrusted.example")
    assert_nil response.headers["Access-Control-Allow-Origin"]
  end
end
