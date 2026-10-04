class AccountMail
  def self.available?
    ActionMailer::Base.delivery_method != :smtp || ENV["SMTP_ADDRESS"].present?
  end

  def self.require_available!
    raise ApiError.new(:email_unavailable, :service_unavailable) unless available?
  end

  def self.encrypt_token(token, user)
    encryptor.encrypt_and_sign(token, purpose: "access_email:#{user.id}")
  end

  def self.decrypt_token(encrypted_token, user)
    encryptor.decrypt_and_verify(encrypted_token, purpose: "access_email:#{user.id}")
  end

  def self.encryptor
    key = Rails.application.key_generator.generate_key("access_email_tokens", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
  end
  private_class_method :encryptor

  def self.deliver(user, token, kind:)
    AuthMailer.with(user: user, encrypted_token: encrypt_token(token, user), kind: kind).access.deliver_later
  end
end
