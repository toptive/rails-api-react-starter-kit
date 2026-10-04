class UploadsPolicy < ApplicationPolicy
  def create? = current_member?
end
