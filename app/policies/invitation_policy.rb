class InvitationPolicy < ApplicationPolicy
  def index? = current_member? && user.membership.manager?
  def create? = index?
  def accept? = user&.user.present?
  def destroy? = index? && (record == Invitation || record.organization_id == user.organization.id)
end
