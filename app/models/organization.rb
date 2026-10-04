class Organization < ApplicationRecord
  has_many :memberships
  has_many :invitations
  normalizes :name, with: ->(value) { value.strip }
  validates :name, presence: true, length: { minimum: 2, maximum: 80 }
  validates :slug, presence: true, uniqueness: { case_sensitive: false }
  before_validation :assign_slug, on: :create
  after_create_commit :track_creation
  after_update_commit :track_onboarding, if: :saved_change_to_onboarded_at?

  attr_accessor :event_actor_id, :onboarding_skipped

  def self.tenancy = Rails.application.config.x.tenancy

  def self.ensure_default!
    insert_all([ { slug: "default", name: I18n.t("organizations.default_name"), personal: false } ], unique_by: :slug)
    find_by!(slug: "default")
  end

  def self.for_user(user)
    joins(:memberships).where(memberships: { user_id: user.id }).order(:created_at, :id).to_a
  end

  def self.scope_for(session)
    return Session::Scope.new unless session

    user = session.user
    organizations = for_user(user)
    if organizations.empty?
      ensure_membership!(user)
      organizations = for_user(user)
    end
    organization = organizations.find { |org| org.id == session.organization_id } ||
      organizations.find { |org| org.id == user.last_organization_id } || organizations.first
    scope = Session::Scope.new(user: user, session: session, organization: organization)
    scope.membership = Membership.for(scope).find_by!(user_id: user.id)
    session.update!(organization: organization) if session.organization_id != organization.id
    scope
  end

  def self.ensure_membership!(user)
    user.with_lock do
      return if for_user(user).any?

      if tenancy == "single"
        organization = ensure_default!
        organization.with_lock do
          scope = Session::Scope.new(organization: organization)
          role = Membership.for(scope).exists? ? "member" : "owner"
          Membership.for(scope).create!(user: user, role: role, access: "full")
        end
      else
        name = user.name.length >= 2 ? user.name : user.email
        organization = create_owned!(user, name: name.slice(0, 80), personal: true)
      end
      user.update!(last_organization_id: organization.id)
    end
  end

  def self.create_owned!(user, name:, personal: false, onboarded: false, session: nil, request: nil)
    transaction do
      organization = create!(name: name, personal: personal, onboarded_at: onboarded ? Time.current : nil,
        event_actor_id: user.id)
      scope = Session::Scope.new(user: user, session: session, organization: organization)
      Membership.for(scope).create!(user: user, role: "owner", access: "full")
      Audit.record("organization.created", scope: scope, subject: organization, request: request)
      organization
    end
  end

  def self.create_current!(scope, attributes, request)
    raise ApiError.forbidden unless tenancy == "multi"

    User::Input.validate!(attributes, string_fields: [ :name ], required: [ :name ])
    transaction do
      organization = create_owned!(scope.user, name: attributes[:name], onboarded: true, session: scope.session, request: request)
      remember!(scope, organization)
      organization
    end
  end

  def self.switch_current!(scope, attributes)
    User::Input.validate!(attributes, string_fields: [ :organization_id ], required: [ :organization_id ])
    organization = for_user(scope.user).find { |org| org.id == attributes[:organization_id] }
    raise ApiError.conflict(:not_member) unless organization

    organization.with_lock do
      destination = Session::Scope.new(user: scope.user, session: scope.session, organization: organization)
      raise ApiError.conflict(:not_member) unless Membership.for(destination).exists?(user_id: scope.user.id)

      remember!(scope, organization)
      Bootstrap.auth_for(scope.session)
    end
  end

  def self.remember!(scope, organization)
    scope.session.update!(organization: organization)
    scope.user.update!(last_organization_id: organization.id)
  end

  def self.settings(scope)
    { organization: scope.organization, can_edit: OrganizationPolicy.new(scope, scope.organization).update? }
  end

  def self.onboarding(scope)
    { organization_name: scope.organization.name, required: scope.organization.onboarded_at.nil? }
  end

  def self.onboarding_required?(scope)
    scope.organization.onboarded_at.nil? && !scope.session.impersonating? && OrganizationPolicy.new(scope, scope.organization).update?
  end

  def self.refresh_membership!(scope)
    scope.membership = Membership.for(scope).find_by(user_id: scope.user.id)
    scope
  end

  def self.update_current!(scope, attributes, request, onboarding: false)
    User::Input.validate!(attributes, string_fields: [ :name ], required: onboarding ? [] : [ :name ])
    organization = scope.organization
    organization.with_lock do
      refresh_membership!(scope)
      Pundit.authorize(scope, organization, onboarding ? :onboarding? : :update?)
      skipped = attributes[:name].to_s.strip.blank?
      organization.name = attributes[:name] unless onboarding && skipped
      if onboarding
        organization.onboarded_at = Time.current
        organization.onboarding_skipped = skipped
        organization.event_actor_id = scope.user.id
      end
      organization.save!
      Audit.record(onboarding ? "organization.onboarded" : "organization.updated", scope: scope, subject: organization, request: request)
      organization
    end
  end

  # Root-only discovery: public capabilities select an organization, never tenant rows.
  def self.for_invitation_token(token_hash)
    joins(:invitations).find_by(invitations: { token_hash: token_hash })
  end

  def self.invited_email?(email)
    joins(:invitations).where(invitations: { email: email, accepted_at: nil })
      .where("invitations.expires_at > ?", Time.current).exists?
  end

  private

  def assign_slug
    self.slug ||= "#{name.to_s.parameterize.slice(0, 40).presence || 'org'}-#{SecureRandom.hex(6)}"
  end

  def track_creation
    ActiveSupport::Notifications.instrument("organization_created", user_id: event_actor_id, organization_id: id) if event_actor_id && !personal?
  end

  def track_onboarding
    ActiveSupport::Notifications.instrument("onboarding_completed", user_id: event_actor_id, organization_id: id, skipped: onboarding_skipped) if event_actor_id
  end
end
