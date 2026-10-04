class MembershipPolicy < ApplicationPolicy
  def index? = current_member?
  def update? = index? && user.membership.manager? && (record == Membership || record.organization_id == user.organization.id)

  def destroy?
    return index? if record == Membership
    return false unless index? && record.organization_id == user.organization.id
    return true if record.user_id == user.user.id

    user.membership.manager? && (record.role != "owner" || user.membership.role == "owner")
  end
end
