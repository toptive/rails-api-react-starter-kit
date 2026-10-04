class OperationsAccess
  COOKIE = "jobs_access"
  LIFETIME = 5.minutes

  def self.matches?(request)
    signed = Rack::Utils.parse_cookies(request.env)[COOKIE]
    session_id = verifier.verified(signed, purpose: :jobs_dashboard) if signed
    session = Session.live.find_by(id: session_id) if session_id
    session&.superadmin? || false
  end

  def self.issue(session, request)
    raise ApiError.not_found unless session.superadmin?

    ticket = JobsTicket.transaction do
      row = JobsTicket.create!(session: session, expires_at: 60.seconds.from_now)
      Audit.record("admin.jobs_dashboard_opened", session: session, subject: session, request: request)
      row
    end
    signed = verifier.generate(ticket.id, expires_in: 60.seconds, purpose: :jobs_ticket)
    { url: "#{Rails.application.config.x.api_origin.delete_suffix('/')}#{Rails.application.routes.url_helpers.admin_jobs_session_path}?#{URI.encode_www_form(ticket: signed)}" }
  end

  def self.exchange(ticket)
    id = verifier.verified(ticket, purpose: :jobs_ticket) if ticket.is_a?(String)
    raise ApiError.not_found unless id.is_a?(String)

    session = JobsTicket.consume!(id)
    signed = verifier.generate(session.id, expires_in: LIFETIME, purpose: :jobs_dashboard)
    Rack::Utils.set_cookie_header(COOKIE, value: signed, path: "/admin/jobs", max_age: LIFETIME.to_i,
      httponly: true, secure: Rails.env.production?, same_site: :strict)
  end

  def self.verifier = Rails.application.message_verifier(:jobs_access)
  private_class_method :verifier
end
