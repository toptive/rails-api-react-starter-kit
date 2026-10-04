Rails.application.config.to_prepare do
  ActionMailer::Base.add_delivery_method :log, AccountMail::LogDelivery
  ActionMailer::Base.add_delivery_method :mailbox, AccountMail::MailboxDelivery if Rails.env.test?
end
