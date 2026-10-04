class ApplicationController < ActionController::API
  include Pundit::Authorization

  around_action :switch_locale
  before_action :normalize_param_keys
  after_action :verify_authorized

  rescue_from ApiError, with: :render_api_error
  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
  rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_invalid_json

  private

  def switch_locale(&action)
    I18n.with_locale(resolve_locale, &action)
  end

  def resolve_locale
    requested = params[:locale]
    tags = requested.is_a?(String) && requested.present? ? [ requested, *accept_language_tags ] : accept_language_tags
    tags.each do |tag|
      [ tag, tag.split("-").first ].each do |candidate|
        locale = I18n.available_locales.find { |available| available.to_s.casecmp?(candidate) }
        return locale if locale
      end
    end
    I18n.default_locale
  rescue ActionDispatch::Http::Parameters::ParseError
    I18n.default_locale
  end

  def accept_language_tags
    request.headers["Accept-Language"].to_s.split(",").filter_map do |entry|
      tag, quality = entry.strip.split(";q=", 2)
      weight = quality ? quality.to_f : 1.0
      [ tag, weight ] if tag.present? && weight.positive?
    end.sort_by { |_, weight| -weight }.map(&:first)
  end

  def normalize_param_keys
    # Locale tags and translation keys are data, not Ruby identifiers.
    params.deep_transform_keys! do |key|
      key.match?(/\A[a-zA-Z][a-zA-Z0-9_]*\z/) ? key.underscore : key
    end
  end

  def render_data(payload, serializer:, status: :ok, meta: {}, serializer_params: {})
    render json: {
      data: serializer.new(payload, params: serializer_params).serializable_hash,
      meta: meta
    }, status: status
  end

  def render_collection(scope, serializer:, status: :ok, serializer_params: {})
    page = params.fetch(:page, 1).to_i.clamp(1, 1_000_000)
    per_page = params.fetch(:per_page, 25).to_i.clamp(1, 100)
    total = scope.count(:all)
    records = scope.limit(per_page).offset((page - 1) * per_page)
    render_data(records, serializer: serializer, status: status, serializer_params: serializer_params,
      meta: { pagination: { page: page, perPage: per_page, total: total, totalPages: [ (total.to_f / per_page).ceil, 1 ].max } })
  end

  def render_api_error(error)
    render_error(code: error.code, status: error.http_status, details: error.details)
  end

  def render_forbidden(_error) = render_error(code: :forbidden, status: :forbidden)
  def render_not_found(_error) = render_error(code: :not_found, status: :not_found)
  def render_invalid_json(_error) = render_error(code: :invalid_json, status: :bad_request)
  def render_rate_limited = render_error(code: :too_many_requests, status: :too_many_requests)

  def render_parameter_missing(error)
    render_error(code: :bad_request, status: :bad_request,
      details: { error.param.to_s.camelize(:lower) => [ "validation.required" ] })
  end

  def render_record_invalid(error)
    details = error.record.errors.group_by(&:attribute).to_h do |field, errors|
      [ field.to_s.camelize(:lower), errors.map { |item| validation_key(item) }.uniq ]
    end
    render_error(code: :validation_failed, status: :unprocessable_entity, details: details)
  end

  def validation_key(error)
    message = error.options[:message]
    return message if message.is_a?(String) && message.start_with?("validation.")
    return error.type if error.type.is_a?(String) && error.type.start_with?("validation.")

    kind = { blank: :required, taken: :unique, too_short: :length_min, too_long: :length_max,
      wrong_length: :length_is, invalid: :format, not_a_number: :cast,
      greater_than: :number_greater_than, less_than: :number_less_than }.fetch(error.type, error.type)
    key = "validation.#{kind}"
    I18n.exists?(key) ? key : "validation.cast"
  end

  def render_error(code:, status:, details: {})
    # rescue_from runs after the locale callback has unwound.
    message = I18n.with_locale(resolve_locale) do
      I18n.t("errors.api.#{code}", default: I18n.t("errors.api.internal_error"))
    end
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    render json: { error: { code: code.to_s, message: message, details: details } }, status: status
  end
end
