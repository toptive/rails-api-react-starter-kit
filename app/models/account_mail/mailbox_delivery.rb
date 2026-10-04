class AccountMail::MailboxDelivery
  def initialize(_settings); end

  def deliver!(mail) = TestMailbox.deliver(mail)
end
