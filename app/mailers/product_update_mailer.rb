class ProductUpdateMailer < ApplicationMailer
  def notice
    @user = params.fetch(:user)
    @app_name = ENV.fetch("APP_NAME", "StarterKit")
    @title = params.fetch(:title)
    @summary = params.fetch(:summary)
    @url = params.fetch(:url)
    @unsubscribe_url = "#{Rails.application.config.x.spa_origin}/email-subscriptions/#{EmailSubscription.token_for(@user)}/opt-out"
    optional_email_headers(@user)
    I18n.with_locale(@user.locale) do
      mail(to: @user.email, from: ENV.fetch("MAIL_FROM_#{@user.locale.upcase}", ENV.fetch("MAIL_FROM", "hello@example.com")),
        subject: I18n.t("mail.product_update.subject", app: @app_name, title: @title), "X-Email-Kind" => "product_update")
    end
  end
end
