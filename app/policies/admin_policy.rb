class AdminPolicy < ApplicationPolicy
  def index? = superadmin?
  def show? = superadmin?
  def create? = superadmin?
  def update? = superadmin?

  private

  def superadmin? = user&.session&.live? && user.session.superadmin?
end
