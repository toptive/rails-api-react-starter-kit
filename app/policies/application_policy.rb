class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = false
  def show? = false
  def create? = false
  def update? = false
  def destroy? = false

  private

  def current_member?
    user&.membership.present? && user.membership.user_id == user.user&.id &&
      user.membership.organization_id == user.organization&.id
  end

  public

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "Policies must explicitly scope their records"
    end

    private

    attr_reader :user, :scope
  end
end
