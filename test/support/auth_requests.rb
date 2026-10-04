module AuthRequests
  extend ActiveSupport::Concern
  include ActiveJob::TestHelper

  included do
    setup do
      Api::V1::BaseController::RATE_LIMIT_STORE.clear
      @saved_auth_env = ENV.to_h.slice("SIGNUP_MODE", "TURNSTILE_REQUIRED", "SPA_ORIGIN", "SMTP_ADDRESS")
      ENV["SIGNUP_MODE"] = "open"
      ENV.delete("TURNSTILE_REQUIRED")
      ActionMailer::Base.deliveries.clear
    end

    teardown do
      %w[SIGNUP_MODE TURNSTILE_REQUIRED SPA_ORIGIN SMTP_ADDRESS].each { |key| ENV[key] = @saved_auth_env[key] }
    end
  end

  def create_user(**attributes)
    User.create!({ name: "Ana", email: "#{SecureRandom.hex(6)}@example.com",
      confirmed_at: Time.current, locale: "en" }.merge(attributes))
  end

  def sign_in(user, password: "strong-password-123")
    user.update!(password: password) unless user.has_password?
    post "/api/v1/auth/sessions", params: { email: user.email, password: password }, as: :json
    assert_response :created
    data.fetch("token")
  end

  def bearer(token) = { "Authorization" => "Bearer #{token}" }
  def data = response.parsed_body.fetch("data")

  def assert_error(status, code)
    assert_response status
    assert_equal code, response.parsed_body.dig("error", "code")
    assert_kind_of Hash, response.parsed_body.dig("error", "details")
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  def request_link(user, headers: {})
    perform_enqueued_jobs do
      post "/api/v1/auth/magic-links", params: { email: user.email }, headers: headers, as: :json
    end
    assert_response :accepted
    mail_token
  end

  def mail_token
    email = ActionMailer::Base.deliveries.last
    email.text_part.body.decoded[%r{/magic-links/([A-Za-z0-9_-]{43})}, 1].tap { |token| assert token }
  end
end
