class BillingSubscriptionPolicy < ApplicationPolicy
  def show? = current_member? && record.organization_id == user.organization.id
end
