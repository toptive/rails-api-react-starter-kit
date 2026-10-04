class UserPolicy < ApplicationPolicy
  def show? = own_user?
  def update? = own_user?
  def destroy? = own_user?

  private

  def own_user? = user&.user&.id == record.id
end
