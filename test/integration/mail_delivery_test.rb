require "test_helper"
require_relative "../support/auth_requests"

class MailDeliveryTest < ActionDispatch::IntegrationTest
  include AuthRequests

  test "magic link mail shares the branded layout and uses the recipient's locale" do
    user = create_user(locale: "es")
    mail = AuthMailer.with(user: user, encrypted_token: AccountMail.encrypt_token("a" * 43, user), kind: "magic_link").access
    assert_equal I18n.t("mail.magic_link.subject", locale: :es, app: "StarterKit"), mail.subject
    assert_includes mail.html_part.body.decoded, 'lang="es"'
    assert_includes mail.text_part.body.decoded, I18n.t("mail.magic_link.action", locale: :es)
  end

  test "development log delivery does not log sign in tokens or email bodies" do
    user = create_user
    previous_delivery = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :log
    messages = []
    Rails.logger.stub(:info, ->(message = nil, &block) { messages << (message || block&.call).to_s }) do
      perform_enqueued_jobs do
        post "/api/v1/auth/magic-links", params: { email: user.email }, as: :json
      end
    end
    assert_response :accepted
    assert messages.any? { |message| message.include?("Development email delivery: magic_link") }
    refute messages.any? { |message| message.include?("/magic-links/") || message.include?(user.email) }
  ensure
    ActionMailer::Base.delivery_method = previous_delivery
  end
end
