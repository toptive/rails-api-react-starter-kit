class Session < ApplicationRecord
  LIFETIME = 14.days
  SUDO_WINDOW = 10.minutes
  Scope = Struct.new(:user, :session, :organization, :membership, keyword_init: true)

  belongs_to :user
  belongs_to :organization, optional: true
  belongs_to :impersonator_user, class_name: "User", optional: true
  belongs_to :impersonator_session, class_name: "Session", optional: true
  belongs_to :impersonation, optional: true
  has_many :impersonation_sessions, class_name: "Session", foreign_key: :impersonator_session_id, dependent: :destroy

  scope :live, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  alias_attribute :impersonator_id, :impersonator_user_id
  alias_attribute :ip, :ip_address
  alias_attribute :last_seen_at, :last_used_at

  def self.create_for(user, request)
    token = SecureRandom.urlsafe_base64(32)
    now = Time.current
    session = create!(user: user, token_hash: Digest::SHA256.digest(token),
      expires_at: now + LIFETIME, authenticated_at: now, sudo_until: now + SUDO_WINDOW,
      ip_address: request.remote_ip, user_agent: request.user_agent&.slice(0, 255), last_used_at: now)
    scope_for(session)
    { session: session, token: token }
  end

  def self.find_by_token(token)
    session = lookup(token)
    return unless session&.live?

    session.touch_usage!
    session
  end

  def self.authenticate(token)
    session = lookup(token)
    raise ApiError.unauthorized unless session
    raise ApiError.unauthorized(:session_expired) unless session.live?

    session.touch_usage!
    session
  end

  def self.lookup(token)
    return unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9_-]{43}\z/)

    find_by(token_hash: Digest::SHA256.digest(token))
  end
  private_class_method :lookup

  def self.scope_for(session)
    Organization.scope_for(session)
  end

  def self.redact_logs!
    return if Rails.logger.formatter.is_a?(LogFormatter)

    Rails.logger.formatter = LogFormatter.new(Rails.logger.formatter)
  end

  def self.purge_expired
    where("COALESCE(revoked_at, expires_at) < ?", 30.days.ago).destroy_all
    UserToken.where("expires_at <= ?", Time.current).delete_all
  end

  def live? = revoked_at.nil? && expires_at > Time.current
  def impersonating? = impersonator_user_id.present?
  def superadmin? = user.role == "superadmin" && !impersonating?
  def sudo? = !impersonating? && sudo_until.present? && sudo_until > Time.current

  def touch_usage!
    now = Time.current
    updates = {}
    updates[:last_used_at] = now if last_used_at.nil? || last_used_at <= now - 1.minute
    if !impersonating? && expires_at < now + 7.days && (renewed_at.nil? || renewed_at <= now - 1.day)
      updates.merge!(expires_at: now + LIFETIME, renewed_at: now)
    end
    update_columns(updates) if updates.any?
  end

  def touch_sudo!
    raise ApiError.forbidden if impersonating?
    raise ApiError.unauthorized(:session_expired) unless live?

    update!(authenticated_at: Time.current, sudo_until: Time.current + SUDO_WINDOW)
    self
  end

  def revoke!(request: nil)
    transaction do
      with_lock do
        return self if revoked_at

        update!(revoked_at: Time.current)
        impersonation_sessions.live.each { |child| child.revoke!(request: request) }
        impersonation&.update!(ended_at: Time.current) if impersonating?
        Audit.record("session.revoked", session: self, subject: self, request: request)
        Audit.record("impersonation.stopped", session: self, subject: impersonation || self, request: request) if impersonating?
      end
    end
    self
  end

  def sign_out!(request)
    transaction do
      # Lock parent before children, matching the cascade revocation order.
      impersonator_session&.revoke!(request: request) if impersonating?
      reload.revoke!(request: request)
    end
  end

  def end_impersonation!(request)
    raise ApiError.conflict(:conflict, { reason: "not_impersonating" }) unless impersonating?

    revoke!(request: request)
  end

  def elevate!(attributes, request)
    raise ApiError.forbidden if impersonating?

    transaction do
      if attributes[:magic_link_token].present?
        UserToken.consume_magic_link!(attributes[:magic_link_token], expected_user: user)
      else
        raise ApiError.unprocessable(:validation_failed, User.validation_details(:password, "validation.required")) unless user.has_password?
        raise ApiError.unauthorized(:invalid_credentials) unless User.password_matches?(user, attributes[:password])
      end
      touch_sudo!
      Audit.record("user.sudo_authenticated", session: self, subject: user, request: request)
    end
    self
  end
end
