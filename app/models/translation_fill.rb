class TranslationFill < ApplicationRecord
  WAIT_SECONDS = 25
  RequestContext = Struct.new(:remote_ip)
  belongs_to :session, optional: true

  def self.start!(attributes, scope, request)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
    locale = Translation.validate_fill!(attributes)
    fill = create!(locale: locale, session: scope.session, ip_address: request.remote_ip)
    FillTranslationsJob.perform_later(fill.id)
    fill.await_result(deadline)
  end

  def self.complete!(id)
    fill = find(id)
    return if fill.completed_at

    scope = fill.session && Session.scope_for(fill.session)
    result = Translation.fill!({ locale: fill.locale }, scope, RequestContext.new(fill.ip_address))
    fill.update!(count: result.fetch(:count), completed_at: Time.current)
  rescue ApiError, Timeout::Error => error
    fill.update!(error_code: error.is_a?(ApiError) ? error.code : "ai_unavailable", completed_at: Time.current)
    Rails.error.report(error)
  end

  def await_result(deadline)
    loop do
      reload
      return { count: nil, status: :accepted } if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      if completed_at
        raise ApiError.unavailable(error_code) if error_code

        return { count: count, status: :created }
      end
      sleep 0.05
    end
  end
end
