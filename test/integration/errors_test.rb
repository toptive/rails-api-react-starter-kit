require "test_helper"

class ErrorsTest < ActionDispatch::IntegrationTest
  test "unknown API routes use a localized envelope for every method" do
    %i[get post put patch delete].each do |method|
      public_send(method, "/api/v1/unknown?locale=es")
      assert_response :not_found
      assert_equal({ "error" => { "code" => "not_found",
        "message" => I18n.t("errors.api.not_found", locale: :es), "details" => {} } }, response.parsed_body)
    end
  end

  test "exception middleware renders 405 415 and 500 without exposing exception messages" do
    previous = ActionDispatch::ExceptionWrapper.rescue_responses["ActionController::UnknownFormat"]
    ActionDispatch::ExceptionWrapper.rescue_responses["ActionController::UnknownFormat"] = :unsupported_media_type
    { ActionController::MethodNotAllowed => [ 405, "method_not_allowed" ],
      ActionController::UnknownHttpMethod => [ 405, "method_not_allowed" ],
      ActionController::UnknownFormat => [ 415, "unsupported_media_type" ],
      StandardError => [ 500, "internal_error" ] }.each do |klass, (status, code)|
      env = Rack::MockRequest.env_for("/api/v1/unknown?locale=es")
      env["action_dispatch.exception"] = klass.new("private exception detail")
      result, headers, body = Rails.application.config.exceptions_app.call(env)
      assert_equal status, result
      assert_equal "private, no-store", headers["cache-control"]
      chunks = []
      body.each { |chunk| chunks << chunk }
      parsed = JSON.parse(chunks.join)
      assert_equal code, parsed.dig("error", "code")
      assert_equal I18n.t("errors.api.#{code}", locale: :es), parsed.dig("error", "message")
      assert_equal({}, parsed.dig("error", "details"))
    end
  ensure
    ActionDispatch::ExceptionWrapper.rescue_responses["ActionController::UnknownFormat"] = previous
  end
end
