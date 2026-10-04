class AccountDeletion
  REASONS = %w[transfer_ownership subscription_active].freeze

  def self.preview(scope)
    { blocker: blocker(scope, Organization.for_user(scope.user)) }
  end

  def self.delete!(scope, request)
    User.transaction do
      organizations = Organization.lock_for_user(scope.user)
      scope.user.lock!
      # Re-read the memberships after waiting for organization locks.
      refusal = blocker(scope, organizations)
      raise ApiError.conflict(refusal.fetch(:reason), { organization: refusal.fetch(:organization) }) if refusal

      organizations.each do |organization|
        tenant = Session::Scope.new(user: scope.user, organization: organization)
        Membership.for(tenant).where(user_id: scope.user.id).destroy_all
      end
      scope.user.destroy!
      Audit.record("user.deleted", scope: scope, subject: scope.user, request: request)
      organizations.each do |organization|
        tenant = Session::Scope.new(organization: organization)
        next if Membership.for(tenant).exists? || BillingSubscription.for(tenant).exists?

        organization.destroy!
        Audit.record("organization.deleted", scope: tenant, actor: scope.user, subject: organization, request: request)
      end
    end
  end

  def self.blocker(scope, organizations)
    organizations.each do |organization|
      tenant = Session::Scope.new(user: scope.user, organization: organization)
      membership = Membership.for(tenant).find_by(user_id: scope.user.id)
      next unless membership

      others = Membership.for(tenant).where.not(user_id: scope.user.id)
      reason = if !others.exists?
        "subscription_active" if BillingSubscription.open?(tenant)
      elsif membership.role == "owner" && !others.exists?(role: "owner")
        "transfer_ownership"
      end
      return { reason: reason, organization: organization.name } if reason
    end
    nil
  end
  private_class_method :blocker
end
