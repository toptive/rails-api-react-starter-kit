require "test_helper"

class MonitoringTest < ActiveSupport::TestCase
  test "Sentry is inactive without a DSN and the reporter does not call it" do
    previous = ENV["SENTRY_DSN"]
    ENV.delete("SENTRY_DSN")
    Sentry.stub(:capture_exception, ->(*) { flunk "No Sentry call without a DSN" }) { assert_nil Monitoring.report(RuntimeError.new("private")) }
  ensure
    ENV["SENTRY_DSN"] = previous
  end

  test "monitoring strips request data breadcrumbs messages and all user data except id" do
    event = Sentry::ErrorEvent.new(configuration: Sentry::Configuration.new)
    event.rack_env = { "rack.input" => StringIO.new("secret-body"), "HTTP_COOKIE" => "secret-cookie", "HTTP_AUTHORIZATION" => "Bearer private", "PATH_INFO" => "/magic-links/private" }
    event.add_exception_interface(RuntimeError.new("private@example.com"), mechanism: Sentry::Mechanism.new)
    event.user = { id: "user-id", email: "private@example.com", ip_address: "127.0.0.1" }
    event.extra = { email: "private@example.com" }
    event.message = "private@example.com"
    event.transaction = "/magic-links/private"
    scrubbed = Monitoring.scrub(event)
    assert_nil scrubbed.request.data
    assert_empty scrubbed.request.headers
    assert_nil scrubbed.request.cookies
    assert_equal({ id: "user-id" }, scrubbed.user)
    assert_empty scrubbed.extra
    assert_nil scrubbed.message
    assert_nil scrubbed.transaction
    refute_includes JSON.generate(scrubbed.to_h), "private"
  end
end
