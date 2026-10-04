class EmailSubscription
  def self.token_for(user)
    verifier.generate([ user.id, Digest::SHA256.hexdigest(user.email.downcase) ], purpose: "email_subscription")
  end

  def self.preview(token)
    payload(resolve!(token))
  end

  def self.opt_out!(token, request)
    user = resolve!(token)
    user.with_lock do
      resolve!(token)
      if user.optional_emails?
        user.update!(optional_emails: false)
        Audit.record("user.optional_emails_stopped", actor: user, subject: user, request: request)
      end
      payload(user)
    end
  end

  def self.resolve!(token)
    identity = verifier.verified(token, purpose: "email_subscription")
    raise ApiError.not_found unless identity.is_a?(Array) && identity.length == 2

    user = User.find_by(id: identity.first)
    raise ApiError.not_found unless user && ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(user.email.downcase), identity.last.to_s)

    user
  end
  private_class_method :resolve!

  def self.verifier = Rails.application.message_verifier("email_subscription")
  private_class_method :verifier

  def self.payload(user) = { email: user.email, subscribed: user.optional_emails }
  private_class_method :payload
end
