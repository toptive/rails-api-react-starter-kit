class User < ApplicationRecord
  ROLES = %w[user superadmin].freeze
  has_many :sessions, dependent: :destroy
  has_many :user_tokens, dependent: :destroy

  attr_accessor :terms_accepted, :password
  normalizes :email, with: ->(value) { value.strip.downcase }
  normalizes :name, with: ->(value) { value.strip }
  validates :name, presence: true, length: { maximum: 120 }
  validates :email, presence: true, length: { maximum: 160 }, uniqueness: { case_sensitive: false },
    format: { with: /\A[^@,;\s]+@[^@,;\s]+\z/, message: "validation.email_format" }
  validates :role, inclusion: { in: ROLES }
  validates :locale, inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } }
  validates :terms_accepted, acceptance: { message: "validation.terms_required", allow_nil: false, accept: [ true, "true" ] }, on: :registration
  validates :password, length: { minimum: 12, maximum: 72 }, allow_nil: true
  validate :password_byte_length
  before_save :hash_password, if: -> { password.present? }

  def has_password? = hashed_password.present?

  def self.signup_mode = ENV.fetch("SIGNUP_MODE", "open")

  def self.register(attributes, request)
    Input.validate!(attributes, string_fields: %i[name email locale turnstile_token], boolean_fields: [ :terms_accepted ], required: %i[name email terms_accepted])
    raise ApiError.unprocessable(:signup_closed) if signup_mode == "closed"
    raise ApiError.unprocessable(:invitation_required) if signup_mode == "invite" && !open_invitation?(attributes[:email])
    AccountMail.require_available!
    Turnstile.verify!(attributes[:turnstile_token], action: "registration", request: request)
    user = new(attributes.slice(:name, :email, :locale, :terms_accepted))
    user.locale ||= I18n.locale.to_s
    token = transaction do
      user.save!(context: :registration)
      accepted = user.record_registration_acceptance!(request)
      Audit.record("user.registered", actor: user, subject: user, metadata: { accepted: accepted }, request: request)
      UserToken.issue_for(user)
    end
    AccountMail.deliver(user, token, kind: "magic_link")
    ActiveSupport::Notifications.instrument("user_registered", user_id: user.id, via: "email")
    { email: user.email, new_account: true }
  rescue ActiveRecord::RecordNotUnique
    user.errors.add(:email, :taken)
    raise ActiveRecord::RecordInvalid.new(user)
  end

  def self.request_magic_link(attributes, request)
    Input.validate!(attributes, string_fields: %i[email turnstile_token], required: [ :email ])
    AccountMail.require_available!
    Turnstile.verify!(attributes[:turnstile_token], action: "magic_link", request: request)
    email = attributes[:email].to_s.strip.downcase
    user = find_by(email: email)
    AccountMail.deliver(user, UserToken.issue_for(user), kind: "magic_link") if user
    { email: email, new_account: false }
  end

  def self.sign_in_password(attributes, request, existing_session: nil)
    Input.validate!(attributes, string_fields: %i[email password], required: %i[email password])
    user = find_by(email: attributes[:email].to_s.strip.downcase)
    matched = password_matches?(user, attributes[:password])
    raise ApiError.unauthorized(:invalid_credentials) unless matched && user.confirmed_at

    user.start_session!(request, existing_session: existing_session, method: "password")
  end

  def self.sign_in_magic_link(token, request, existing_session: nil)
    transaction do
      user, new_account = UserToken.consume_magic_link!(token)
      user.start_session!(request, existing_session: existing_session, method: "magic_link", new_account: new_account)
    end
  end

  def self.password_matches?(user, password)
    # A real bcrypt comparison also runs for unknown users and passwordless accounts.
    hash = user&.hashed_password || dummy_password_hash
    matched = BCrypt::Password.new(hash).is_password?(password.is_a?(String) ? password : "")
    matched && user&.has_password? && password.is_a?(String) && password.bytesize.between?(1, 72)
  end

  def self.dummy_password_hash
    @dummy_password_hash ||= BCrypt::Password.create(SecureRandom.hex(32)).to_s
  end

  def self.validation_details(field, key, **bindings)
    detail = { key: key, message: I18n.t(key, **bindings) }
    detail[:bindings] = bindings if bindings.any?
    { field.to_s.camelize(:lower) => [ detail ] }
  end

  def start_session!(request, existing_session: nil, method:, new_account: false)
    issued = if existing_session&.user_id == id
      { session: existing_session.touch_sudo!, token: nil }
    else
      Session.create_for(self, request)
    end
    session = issued.fetch(:session)
    ActiveSupport::Notifications.instrument("user_signed_in", user_id: id, method: method)
    ActiveSupport::Notifications.instrument("signup_confirmed", user_id: id) if new_account
    { token: issued[:token], expires_at: session.expires_at, sudo_until: session.sudo_until,
      user: self, impersonator: session.impersonator_user, new_account: new_account }
  end

  def record_registration_acceptance!(request)
    update!(legal_accepted_at: Time.current, legal_accepted_ip_address: request.remote_ip)
    legal_accepted_versions.keys
  end

  def self.open_invitation?(email)
    Invitation.open_for_email?(email.to_s.strip.downcase)
  end
  private_class_method :open_invitation?

  private

  def hash_password
    self.hashed_password = BCrypt::Password.create(password).to_s
    self.password = nil
  end

  def password_byte_length
    errors.add(:password, :too_long, count: 72) if password && password.bytesize > 72
  end
end
