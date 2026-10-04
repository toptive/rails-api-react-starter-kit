class OperationsAccess
  COOKIE = "jobs_access"
  LIFETIME = 5.minutes

  def self.matches?(request)
    signed = Rack::Utils.parse_cookies(request.env)[COOKIE]
    session_id = verifier.verified(signed, purpose: :jobs_dashboard) if signed
    session = Session.live.find_by(id: session_id) if session_id
    session&.superadmin? || false
  end

  def self.issue(session)
    raise ApiError.not_found unless session.superadmin?

    signed = verifier.generate(session.id, expires_in: LIFETIME, purpose: :jobs_dashboard)
    Rack::Utils.set_cookie_header(COOKIE, value: signed, path: "/jobs", max_age: LIFETIME.to_i,
      httponly: true, secure: Rails.env.production?, same_site: :strict)
  end

  def self.verifier = Rails.application.message_verifier(:jobs_access)
  private_class_method :verifier
end
