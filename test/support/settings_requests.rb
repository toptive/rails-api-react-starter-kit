require_relative "tenancy_requests"

module SettingsRequests
  extend ActiveSupport::Concern
  include TenancyRequests

  def change_email(email, headers: bearer(@owner_token))
    perform_enqueued_jobs do
      put "/api/v1/settings/email", params: { email: email }, headers: headers, as: :json
    end
    assert_response :accepted
    assert_equal({ "email" => email.strip.downcase }, data)
    mail = ActionMailer::Base.deliveries.last
    mail.text_part.body.decoded[%r{/settings/email-confirmations/([A-Za-z0-9_-]{43})}, 1].tap { |token| assert token }
  end
end
