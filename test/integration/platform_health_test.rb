require "test_helper"

class PlatformHealthTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  test "readiness probe checks the actual database and stays text and no store" do
    get "/health"
    assert_response :ok
    assert_equal "ok", response.body
    assert_equal "text/plain", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Set-Cookie"]
  end

  test "readiness returns 503 when the configured database cannot connect" do
    original = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.establish_connection(original.merge(host: "127.0.0.1", port: 1, connect_timeout: 1))
    get "/health"
    assert_response :service_unavailable
    assert_equal "database unavailable", response.body
    assert_equal "text/plain", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
  ensure
    ActiveRecord::Base.establish_connection(original)
  end
end
