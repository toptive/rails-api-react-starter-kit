class AccountMail::LogDelivery
  def initialize(_settings = {})
  end

  def deliver!(mail)
    Rails.logger.info("Development email delivery: #{mail.header['X-Email-Kind']}")
  end
end
