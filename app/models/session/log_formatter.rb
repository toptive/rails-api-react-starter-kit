class Session::LogFormatter
  delegate_missing_to :@formatter
  def initialize(formatter)
    @formatter = formatter || ActiveSupport::Logger::SimpleFormatter.new
  end

  def call(severity, time, program, message)
    # Auth tokens can occur in route segments and queued mail, beyond parameter filtering.
    filtered = message.to_s.gsub(/(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])/, "[FILTERED]")
    @formatter.call(severity, time, program, filtered)
  end
end
