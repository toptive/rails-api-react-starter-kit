class TranslationFill < ApplicationRecord
  WAIT_SECONDS = 25
  RequestContext = Struct.new(:remote_ip)
  belongs_to :session, optional: true

  def self.start!(attributes, scope, request)
    locale = Translation.validate_fill!(attributes)
    fill = create!(locale: locale, session: scope.session, ip_address: request.remote_ip)
    FillTranslationsJob.perform_later(fill.id)
    fill.await_result
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

  def await_result
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
    until reload.completed_at
      return { count: nil, status: :accepted } if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
    raise ApiError.unavailable(error_code) if error_code

    { count: count, status: :created }
  end
end
