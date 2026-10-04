class SessionPolicy < ApplicationPolicy
  def destroy? = own_session?
  def update? = own_session? && !record.impersonating?

  private

  def own_session? = user&.user&.id == record.user_id && user&.session&.id == record.id
end
