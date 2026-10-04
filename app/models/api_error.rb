# Domain errors carry stable codes; the controller translates the message.
class ApiError < StandardError
  attr_reader :code, :http_status, :details

  def initialize(code, http_status, details = {})
    @code = code.to_s
    @http_status = http_status
    @details = details
    super(@code)
  end

  def self.for_unmatched_route(request)
    known_path = Rails.application.routes.routes.any? do |route|
      route.defaults[:controller].to_s.start_with?("api/v1/") && route.path.match(request.path)
    end
    known_path ? new(:method_not_allowed, :method_not_allowed) : not_found
  end

  def self.bad_request(code = :bad_request, details = {}) = new(code, :bad_request, details)
  def self.unauthorized(code = :unauthorized, details = {}) = new(code, :unauthorized, details)
  def self.forbidden(code = :forbidden, details = {}) = new(code, :forbidden, details)
  def self.not_found(code = :not_found, details = {}) = new(code, :not_found, details)
  def self.conflict(code = :conflict, details = {}) = new(code, :conflict, details)
  def self.unprocessable(code = :validation_failed, details = {}) = new(code, :unprocessable_entity, details)
  def self.too_many_requests(code = :rate_limited, details = {}) = new(code, :too_many_requests, details)
end
