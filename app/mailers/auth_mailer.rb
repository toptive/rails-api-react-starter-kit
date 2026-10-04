class AuthMailer < ApplicationMailer
  def access
    @user = params.fetch(:user)
    @kind = params.fetch(:kind)
    @app_name = ENV.fetch("APP_NAME", "StarterKit")
    token = AccountMail.decrypt_token(params.fetch(:encrypted_token), @user)
    path = @kind == "email_change" ? "/settings/email-confirmations/#{token}" : "/magic-links/#{token}"
    @url = "#{Rails.application.config.x.spa_origin.delete_suffix('/')}#{path}"
    I18n.with_locale(@user.locale) do
      sender = ENV.fetch("MAIL_FROM_#{@user.locale.upcase}", ENV.fetch("MAIL_FROM", "hello@example.com"))
      sender_name = ENV.fetch("MAIL_FROM_NAME_#{@user.locale.upcase}", ENV.fetch("MAIL_FROM_NAME", @app_name))
      mail(to: params.fetch(:email, @user.email), from: email_address_with_name(sender, sender_name),
        subject: I18n.t("mail.#{@kind}.subject", app: @app_name), "X-Email-Kind" => @kind)
    end
  end
end
