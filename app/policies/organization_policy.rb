class OrganizationPolicy < ApplicationPolicy
  def create? = user&.user.present? && Organization.tenancy == "multi"
  def switch? = user&.user.present?
  def show? = same_organization? && current_member?
  def update? = show? && user.membership.manager?
  def onboarding? = update? && !user.session.impersonating?

  private

  def same_organization? = record.is_a?(Organization) && user&.organization&.id == record.id
end
