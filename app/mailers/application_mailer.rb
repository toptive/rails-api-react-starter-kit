class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  private

  def optional_email_headers(user)
    token = EmailSubscription.token_for(user)
    path = Rails.application.routes.url_helpers.api_v1_email_subscription_opt_out_path(token)
    url = "#{Rails.application.config.x.api_origin.delete_suffix('/')}#{path}"
    headers["List-Unsubscribe"] = "<#{url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
  end
end
