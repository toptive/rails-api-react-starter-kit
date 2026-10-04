class ApiException
  def self.from_request(request)
    status = ActionDispatch::ExceptionWrapper.new(nil, request.env["action_dispatch.exception"]).status_code
    code = { 400 => :bad_request, 404 => :not_found, 405 => :method_not_allowed,
      415 => :unsupported_media_type }.fetch(status, :internal_error)
    ApiError.new(code, status)
  end
end
