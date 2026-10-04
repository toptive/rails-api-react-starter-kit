class BillingPolicy < ApplicationPolicy
  def show? = current_member?
  def create? = current_member? && user.membership.access == "full" && %w[owner admin].include?(user.membership.role)
end
