class InvitationMailer < ApplicationMailer
  def invitation
    invitation = params.fetch(:invitation)
    @app_name = ENV.fetch("APP_NAME", "StarterKit")
    @organization = invitation.organization.name
    @inviter = invitation.invited_by&.name || @organization
    token = AccountMail.decrypt_token(params.fetch(:encrypted_token), invitation)
    @url = "#{Rails.application.config.x.spa_origin.delete_suffix('/')}/invitations/#{token}"
    I18n.with_locale(params.fetch(:locale)) do
      sender = ENV.fetch("MAIL_FROM_#{I18n.locale.to_s.upcase}", ENV.fetch("MAIL_FROM", "hello@example.com"))
      sender_name = ENV.fetch("MAIL_FROM_NAME_#{I18n.locale.to_s.upcase}", ENV.fetch("MAIL_FROM_NAME", @app_name))
      mail(to: invitation.email, from: email_address_with_name(sender, sender_name),
        subject: I18n.t("mail.invitation.subject", inviter: @inviter, organization: @organization), "X-Email-Kind" => "invitation")
    end
  end
end
