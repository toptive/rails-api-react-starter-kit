class Monitoring
  def self.report(exception, context = {})
    return if ENV["SENTRY_DSN"].blank?

    Sentry.capture_exception(exception) { |scope| scope.set_user(id: context[:user_id]) if context[:user_id] }
  end

  def self.scrub(event, _hint = nil)
    if request = event.request
      request.data = nil
      request.cookies = nil
      request.headers = {}
      request.env = {}
      request.url = nil
      request.query_string = nil
    end
    event.user = event.user.slice(:id, "id")
    event.extra = {}
    event.contexts = {}
    event.tags = {}
    event.attachments = []
    event.breadcrumbs = Sentry::BreadcrumbBuffer.new
    event.transaction = nil
    event.message = nil
    event.exception&.values&.each do |exception|
      exception.value = exception.type
      exception.stacktrace&.frames&.each { |frame| frame.vars = nil }
    end
    event
  end
end
