class RenewalNoticeMailer < ApplicationMailer
  def notice
    @user = params.fetch(:user)
    @organization = params.fetch(:organization)
    @subscription = params.fetch(:subscription)
    @app_name = ENV.fetch("APP_NAME", "StarterKit")
    preview = params.fetch(:preview)
    @amount = format("%.2f %s", preview.fetch("amount_due") / 100.0, preview.fetch("currency").upcase)
    @date = @subscription.current_period_end.utc.strftime("%Y-%m-%d")
    @url = "#{Billing.public_url}/settings/billing"
    I18n.with_locale(@user.locale) do
      sender = ENV.fetch("MAIL_FROM_#{@user.locale.upcase}", ENV.fetch("MAIL_FROM", "hello@example.com"))
      mail(to: @user.email, from: email_address_with_name(sender, @app_name),
        subject: I18n.t("mail.renewal_notice.subject", app: @app_name, date: @date), "X-Email-Kind" => "renewal_notice")
    end
  end
end
