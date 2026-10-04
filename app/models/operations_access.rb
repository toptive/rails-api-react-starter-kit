# Route constraint for the HTML job dashboard; never expose it anonymously.
class OperationsAccess
  def self.matches?(request)
    token = request.authorization.to_s[/\ABearer ([^\s,]+)\z/i, 1]
    session = find_session(token)
    session && session.user.role == "superadmin" && session.impersonator_id.nil?
  end

  # Session digest/expiry lookup is supplied with the authentication domain.
  def self.find_session(_token) = nil
  private_class_method :find_session
end
