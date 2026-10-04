class Invitation < ApplicationRecord
  include TenantScoped

  LIFETIME = 7.days
  belongs_to :invited_by, class_name: "User", optional: true
  normalizes :email, with: ->(value) { value.strip.downcase }
  validates :email, presence: true, length: { maximum: 160 },
    format: { with: /\A[^@,;\s]+@[^@,;\s]+\z/, message: "validation.email_format" }
  validates :role, inclusion: { in: Membership::ROLES }, exclusion: { in: [ "owner" ], message: "validation.invitation_owner" }
  validates :access, inclusion: { in: Membership::ACCESSES }
  after_create_commit :queue_delivery
  after_update_commit :track_acceptance, if: :saved_change_to_accepted_at?

  attr_accessor :encrypted_delivery_token, :delivery_locale, :event_actor_id

  def open? = accepted_at.nil? && expires_at > Time.current
  def self.open_for_email?(email) = Organization.invited_email?(email)

  def self.list(scope)
    self.for(scope).where(accepted_at: nil).where("expires_at > ?", Time.current).order(created_at: :desc, id: :desc)
  end

  def self.issue!(scope, attributes, request)
    AccountMail.require_available!
    User::Input.validate!(attributes, string_fields: %i[email role access], required: [ :email ])
    scope.organization.with_lock do
      Organization.refresh_membership!(scope)
      Pundit.authorize(scope, self, :create?)
      token = SecureRandom.urlsafe_base64(32)
      invitation = self.for(scope).new(attributes.slice(:email, :role, :access).merge(
        invited_by: scope.user, expires_at: Time.current + LIFETIME, token_hash: Digest::SHA256.digest(token)))
      invitation.valid?
      if Membership.for(scope).joins(:user).exists?(users: { email: invitation.email })
        invitation.errors.add(:email, "validation.already_member")
      end
      if list(scope).exists?(email: invitation.email)
        invitation.errors.add(:email, "validation.invitation_pending")
      end
      raise ActiveRecord::RecordInvalid.new(invitation) if invitation.errors.any?

      self.for(scope).where(email: invitation.email, accepted_at: nil).where("expires_at <= ?", Time.current).delete_all
      invitation.delivery_locale = I18n.locale.to_s
      invitation.event_actor_id = scope.user.id
      invitation.save!
      invitation.encrypted_delivery_token = AccountMail.encrypt_token(token, invitation)
      Audit.record("invitation.created", scope: scope, subject: invitation, metadata: { email: invitation.email }, request: request)
      invitation
    end
  end

  def self.preview(token, user)
    invitation = resolve_token!(token)
    { organization: invitation.organization.name, email: invitation.email, role: invitation.role,
      access: invitation.access, expires_at: invitation.expires_at, email_matches: user&.email&.casecmp?(invitation.email) || false }
  end

  def self.accept!(scope, token, request)
    invitation = resolve_token!(token)
    invitation.organization.with_lock do
      destination = Session::Scope.new(user: scope.user, session: scope.session, organization: invitation.organization)
      invitation = self.for(destination).find(invitation.id)
      raise ApiError.unprocessable(:invitation_invalid) unless invitation.open?
      raise ApiError.conflict(:email_mismatch, { email: invitation.email }) unless scope.user.email.casecmp?(invitation.email)

      membership = Membership.for(destination).find_or_create_by!(user: scope.user) do |member|
        member.role = invitation.role
        member.access = invitation.access
      end
      invitation.event_actor_id = scope.user.id
      invitation.update!(accepted_at: Time.current)
      Organization.remember!(destination, destination.organization)
      Audit.record("invitation.accepted", scope: destination, subject: invitation, request: request)
      membership
    end
  end

  def self.revoke!(scope, id, request)
    scope.organization.with_lock do
      Organization.refresh_membership!(scope)
      invitation = self.for(scope).find(id)
      Pundit.authorize(scope, invitation, :destroy?)
      invitation.destroy!
      Audit.record("invitation.revoked", scope: scope, subject: invitation, metadata: { email: invitation.email }, request: request)
      invitation
    end
  end

  def self.purge_expired
    Organization.find_each do |organization|
      scope = Session::Scope.new(organization: organization)
      self.for(scope).where("expires_at <= ?", Time.current).delete_all
    end
  end

  def self.deliver_notification(organization_id, id, encrypted_token, locale)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    scope = Session::Scope.new(organization: organization)
    invitation = self.for(scope).find_by(id: id)
    return unless invitation&.open?
    return unless allowed_recipient?(invitation.email)

    AccountMail.require_available!
    InvitationMailer.with(invitation: invitation, encrypted_token: encrypted_token, locale: locale).invitation.deliver_now
  end

  def self.allowed_recipient?(email)
    return true if Rails.env.production? || ENV["MAIL_ALLOWED_RECIPIENTS"].blank?

    allowed = ENV.fetch("MAIL_ALLOWED_RECIPIENTS").split(",").any? do |pattern|
      File.fnmatch?(pattern.strip.downcase, email.downcase)
    end
    Rails.logger.info("Invitation delivery cancelled by recipient allow-list") unless allowed
    allowed
  end
  private_class_method :allowed_recipient?

  def self.resolve_token!(token)
    raise ApiError.unprocessable(:invitation_invalid) unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9_-]{43}\z/)

    token_hash = Digest::SHA256.digest(token)
    organization = Organization.for_invitation_token(token_hash)
    raise ApiError.unprocessable(:invitation_invalid) unless organization

    scope = Session::Scope.new(organization: organization)
    invitation = self.for(scope).find_by(token_hash: token_hash)
    raise ApiError.unprocessable(:invitation_invalid) unless invitation&.open?

    invitation
  end
  private_class_method :resolve_token!

  private

  def queue_delivery
    return unless encrypted_delivery_token

    InvitationDeliveryJob.perform_later(organization_id, id, encrypted_delivery_token, delivery_locale)
    ActiveSupport::Notifications.instrument("invitation_sent", user_id: event_actor_id, organization_id: organization_id, role: role)
  end

  def track_acceptance
    ActiveSupport::Notifications.instrument("invitation_accepted", user_id: event_actor_id, organization_id: organization_id) if event_actor_id
  end
end
