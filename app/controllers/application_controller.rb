class ApplicationController < ActionController::API
  include Pundit::Authorization

  around_action :switch_locale
  before_action :require_json_body
  before_action :normalize_param_keys
  after_action :verify_authorized

  rescue_from ApiError, with: :render_api_error
  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
  rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_invalid_json
  before_action :set_private_cache

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
    I18n.available_locales.find { |locale| locale.to_s == locale_user&.locale_in_database } || I18n.default_locale
  rescue ActionDispatch::Http::Parameters::ParseError
    I18n.default_locale
  end

  def locale_user = nil

  def accept_language_tags
    request.headers["Accept-Language"].to_s.split(",").filter_map do |entry|
      tag, quality = entry.strip.split(";q=", 2)
      weight = quality ? quality.to_f : 1.0
      [ tag, weight ] if tag.present? && weight.positive?
    end.sort_by { |_, weight| -weight }.map(&:first)
  end

  def require_json_body
    return unless request.content_length.to_i.positive?
    return if request.media_type == "application/json"

    raise ApiError.new(:unsupported_media_type, :unsupported_media_type)
  end

  def normalize_param_keys
    # Locale tags and translation keys are data, not Ruby identifiers.
    params.deep_transform_keys! do |key|
      key.match?(/\A[a-zA-Z][a-zA-Z0-9_]*\z/) ? key.underscore : key
    end
  end

  def cast_string_attributes(*fields)
    fields.each do |field|
      next unless params.key?(field)
      next if params[field].is_a?(String)

      raise ApiError.bad_request(:bad_request, User.validation_details(field, "validation.cast"))
    end
    params.permit(*fields).to_h.symbolize_keys
  end

  def render_data(payload, serializer:, status: :ok, meta: {}, serializer_params: {})
    render json: {
      data: serializer.new(payload, params: serializer_params).serializable_hash,
      meta: meta
    }, status: status
  end

  def render_webhook_receipt(payload)
    render json: WebhookReceiptSerializer.new(payload).serializable_hash, status: :ok
  end

  def render_catalogue(catalogue)
    response.headers["ETag"] = catalogue.fetch(:etag)
    response.headers["Cache-Control"] = "public, no-cache"
    if request.fresh?(response)
      head :not_modified
    else
      render_data(catalogue.fetch(:catalogue), serializer: LocaleSerializer,
        meta: catalogue.slice(:locale, :version))
    end
  end

  def render_legal_page(page)
    response.headers["ETag"] = page.fetch(:etag)
    response.headers["Cache-Control"] = "public, no-cache"
    if request.fresh?(response)
      head :not_modified
    else
      render_data(page, serializer: LegalPageSerializer)
    end
  end

  def cast_legal_attributes
    attributes = params.permit(:note, :publish, titles: {}, bodies: {}).to_h.symbolize_keys
    %i[titles bodies].each do |field|
      value = params[field]
      attributes[field] = value if params.key?(field) && !value.is_a?(ActionController::Parameters)
    end
    attributes
  end

  def render_collection(scope, serializer:, status: :ok, serializer_params: {})
    page = params.fetch(:page, 1).to_s.to_i.clamp(1, 1_000_000)
    per_page = params.fetch(:per_page, 25).to_s.to_i.clamp(1, 100)
    total = scope.is_a?(Array) ? scope.size : scope.count(:all)
    records = scope.is_a?(Array) ? scope.slice((page - 1) * per_page, per_page).to_a : scope.limit(per_page).offset((page - 1) * per_page)
    render_data(records, serializer: serializer, status: status, serializer_params: serializer_params,
      meta: { pagination: { page: page, perPage: per_page, total: total, totalPages: [ (total.to_f / per_page).ceil, 1 ].max } })
  end

  def render_api_error(error)
    render_error(code: error.code, status: error.http_status, details: error.details)
  end

  def render_forbidden(_error) = render_error(code: :forbidden, status: :forbidden)
  def render_not_found(_error) = render_error(code: :not_found, status: :not_found)
  def render_invalid_json(_error) = render_error(code: :invalid_json, status: :bad_request)
  def set_private_cache
    response.headers["Cache-Control"] = "private, no-store"
  end

  def render_rate_limited
    response.headers["Retry-After"] = "60"
    render_error(code: :rate_limited, status: :too_many_requests, details: { retryAfter: 60 })
  end

  def render_parameter_missing(error)
    render_error(code: :bad_request, status: :bad_request,
      details: { error.param.to_s.camelize(:lower) => [ validation_detail("validation.required") ] })
  end

  def render_record_invalid(error)
    details = error.record.errors.group_by(&:attribute).to_h do |field, errors|
      [ field.to_s.camelize(:lower), errors.map { |item| validation_detail(validation_key(item), item.options.slice(:count)) }.uniq ]
    end
    render_error(code: :validation_failed, status: :unprocessable_entity, details: details)
  end

  def validation_detail(key, bindings = {})
    detail = { key: key, message: I18n.t(key, **bindings, locale: resolve_locale) }
    detail[:bindings] = bindings if bindings.present?
    detail
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
