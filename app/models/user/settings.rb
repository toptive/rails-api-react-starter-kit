class User::Settings
  def initialize(user)
    @user = user
  end

  def profile!(attributes)
    User::Input.validate!(attributes, string_fields: %i[name locale])
    user.update!(attributes.slice(:name, :locale))
    user
  end

  def preferences!(attributes, scope, request)
    User::Input.validate!(attributes, string_fields: [], boolean_fields: [ :optional_emails ], required: [ :optional_emails ])
    user.with_lock do
      value = ActiveModel::Type::Boolean.new.cast(attributes[:optional_emails])
      if user.optional_emails != value
        user.update!(optional_emails: value)
        Audit.record(value ? "user.optional_emails_started" : "user.optional_emails_stopped", scope: scope, subject: user, request: request)
      end
      user
    end
  end

  def email!(attributes)
    AccountMail.require_available!
    User::Input.validate!(attributes, string_fields: [ :email ], required: [ :email ])
    user.with_lock do
      email = attributes[:email].strip.downcase
      raise ApiError.conflict(:email_unchanged, User.validation_details(:email, "validation.email_unchanged")) if email == user.email

      candidate = user.dup
      candidate.email = email
      candidate.validate!
      UserToken.issue_for(user, context: "change_email:#{user.email}", sent_to: email, deliver_email_change: true)
      { email: email }
    end
  end

  def confirm_email!(token, scope, request)
    user.with_lock do
      row = UserToken.email_change!(user, token)
      user.update!(email: row.sent_to)
      user.user_tokens.where("context LIKE ?", "change_email:%").delete_all
      Audit.record("user.email_changed", scope: scope, subject: user, request: request)
      user
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    raise ApiError.unprocessable(:email_change_invalid)
  end

  def password!(attributes, scope, request)
    User::Input.validate!(attributes, string_fields: %i[password password_confirmation], required: %i[password password_confirmation])
    user.with_lock do
      user.password = attributes[:password]
      user.valid?
      if attributes[:password] != attributes[:password_confirmation]
        user.errors.add(:password_confirmation, "validation.password_mismatch")
      end
      raise ActiveRecord::RecordInvalid.new(user) if user.errors.any?

      user.save!
      # Keep known bearer hashes so old devices receive session_expired rather than unauthorized.
      user.sessions.live.order(:id).each { |session| session.revoke!(request: request, audit: session.id != scope.session.id) }
      user.user_tokens.delete_all
      issued = Session.create_for(user, request)
      session = issued.fetch(:session)
      session.update!(organization: scope.organization)
      Audit.record("user.password_changed", scope: scope, subject: user, request: request)
      { token: issued.fetch(:token), expires_at: session.expires_at, sudo_until: session.sudo_until,
        user: user, impersonator: nil, new_account: false, can_manage: session.can_manage? }
    end
  end

  private

  attr_reader :user
end
