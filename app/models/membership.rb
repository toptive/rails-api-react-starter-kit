class Membership < ApplicationRecord
  include TenantScoped

  ROLES = %w[owner admin member].freeze
  ACCESSES = %w[full viewer].freeze
  belongs_to :user
  validates :role, inclusion: { in: ROLES }
  validates :access, inclusion: { in: ACCESSES }
  validates :user_id, uniqueness: { scope: :organization_id }

  def manager? = role.in?(%w[owner admin]) && access == "full"

  def self.list(scope)
    self.for(scope).includes(:user).order(:created_at, :id)
  end

  def self.update_member!(scope, id, attributes, request)
    User::Input.validate!(attributes, string_fields: %i[role access])
    scope.organization.with_lock do
      Organization.refresh_membership!(scope)
      Pundit.authorize(scope, self, :update?)
      membership = self.for(scope).find(id)
      role = attributes.fetch(:role, membership.role)
      if (membership.role == "owner" || role == "owner") && scope.membership.role != "owner"
        raise ApiError.unprocessable(:validation_failed, User.validation_details(:role, "validation.owner_only"))
      end
      if membership.role == "owner" && role != "owner" && last_owner?(scope)
        raise ApiError.unprocessable(:validation_failed, User.validation_details(:role, "validation.last_owner"))
      end
      membership.update!(attributes.slice(:role, :access))
      Audit.record("membership.updated", scope: scope, subject: membership,
        metadata: { role: membership.role, access: membership.access }, request: request)
      membership
    end
  end

  def self.remove_member!(scope, id, request)
    scope.organization.with_lock do
      Organization.refresh_membership!(scope)
      membership = self.for(scope).find(id)
      Pundit.authorize(scope, membership, :destroy?)
      raise ApiError.conflict(:last_owner) if membership.role == "owner" && last_owner?(scope)

      membership.destroy!
      Audit.record("membership.deleted", scope: scope, subject: membership, metadata: { user_id: membership.user_id }, request: request)
      if membership.user_id == scope.user.id
        current = Organization.scope_for(scope.session)
        Organization.remember!(current, current.organization)
      else
        Audit.record("organization.member_removed", scope: scope, subject: membership, metadata: { user_id: membership.user_id }, request: request)
      end
      membership
    end
  end

  def self.last_owner?(scope)
    self.for(scope).where(role: "owner").count <= 1
  end
  private_class_method :last_owner?
end
