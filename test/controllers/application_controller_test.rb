require "test_helper"

# Test-only endpoints exercise the shared boundary without adding domain routes.
class BoundaryProbeController < ApplicationController
  def show
    skip_authorization unless params[:kind] == "missing_authorization"
    case params[:kind]
    when "unauthorized"
      raise ApiError.unauthorized
    when "forbidden"
      raise Pundit::NotAuthorizedError
    when "not_found"
      raise ActiveRecord::RecordNotFound
    when "invalid_record"
      record = BoundaryRecord.new
      record.valid?
      raise ActiveRecord::RecordInvalid.new(record)
    when "missing_parameter"
      params.require(:display_name)
    when "collection"
      count = params.fetch(:size, 3).to_i
      render_collection(BoundaryScope.new(Array.new(count) { { status: "ok" } }), serializer: HealthSerializer)
    when "locale"
      render_data({ status: I18n.locale.to_s }, serializer: HealthSerializer)
    else
      render_data({ status: params.require(:display_name) }, serializer: HealthSerializer, status: :created)
    end
  end
end

class ProtectedProbeController < Api::V1::BaseController
  def show
    skip_authorization
    render_data({ status: "ok" }, serializer: HealthSerializer)
  end
end

class BoundaryRecord
  include ActiveModel::Model
  attr_accessor :display_name
  validates :display_name, presence: true
end

class BoundaryScope
  def initialize(rows)
    @rows = rows
  end

  def count(_column) = @rows.size
  def limit(amount)
    @limit = amount
    self
  end

  def offset(amount) = @rows.drop(amount).take(@limit)
end

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_locale = I18n.locale
  end

  teardown do
    assert_equal @previous_locale, I18n.locale, "request locale must not leak"
  end

  test "query locale overrides the header and regional headers fall back" do
    with_probe_routes do
      get "/probe/locale?locale=en", headers: { "Accept-Language" => "es-AR" }
      assert_equal "en", response.parsed_body.dig("data", "status")
      get "/probe/locale", headers: { "Accept-Language" => "fr,es-AR;q=0.8,en;q=0.2" }
      assert_equal "es", response.parsed_body.dig("data", "status")
      get "/probe/locale?locale=unsupported", headers: { "Accept-Language" => "es" }
      assert_equal "es", response.parsed_body.dig("data", "status")
      get "/probe/locale", headers: { "Accept-Language" => "es;q=0,en" }
      assert_equal "en", response.parsed_body.dig("data", "status")
    end
  end

  test "errors use the request locale even after the action unwinds" do
    with_probe_routes do
      { "unauthorized" => 401, "forbidden" => 403, "not_found" => 404 }.each do |code, status|
        get "/probe/#{code}?locale=es"
        assert_response status
        assert_equal({ "error" => { "code" => code,
          "message" => I18n.t("errors.api.#{code}", locale: :es), "details" => {} } }, response.parsed_body)
        assert_equal "private, no-store", response.headers["Cache-Control"]
      end
    end
  end

  test "invalid models return camelCase fields and translation keys" do
    with_probe_routes do
      get "/probe/invalid_record?locale=es"
      assert_response :unprocessable_entity
      assert_equal "validation_failed", response.parsed_body.dig("error", "code")
      assert_equal({ "displayName" => [ { "key" => "validation.required", "message" => I18n.t("validation.required", locale: :es) } ] }, response.parsed_body.dig("error", "details"))
    end
  end

  test "flat camelCase input is normalized and missing input has a 400 envelope" do
    with_probe_routes do
      post "/probe/input", params: { displayName: "ok" }, as: :json
      assert_response :created
      assert_equal "ok", response.parsed_body.dig("data", "status")
      get "/probe/missing_parameter"
      assert_response :bad_request
      assert_equal "bad_request", response.parsed_body.dig("error", "code")
      assert_equal({ "displayName" => [ { "key" => "validation.required", "message" => I18n.t("validation.required") } ] }, response.parsed_body.dig("error", "details"))
    end
  end

  test "malformed JSON is contained by the boundary" do
    with_probe_routes do
      post "/probe/input", params: "{invalid", headers: { "Content-Type" => "application/json" }
      assert_response :bad_request
      assert_equal "invalid_json", response.parsed_body.dig("error", "code")
    end
  end

  test "collections clamp pagination and empty collections have one page" do
    with_probe_routes do
      get "/probe/collection?page=2&perPage=2"
      assert_equal [ { "status" => "ok" } ], response.parsed_body.fetch("data")
      assert_equal({ "page" => 2, "perPage" => 2, "total" => 3, "totalPages" => 2 },
        response.parsed_body.dig("meta", "pagination"))
      get "/probe/collection?page=-1&perPage=200&size=0"
      assert_equal [], response.parsed_body.fetch("data")
      assert_equal({ "page" => 1, "perPage" => 100, "total" => 0, "totalPages" => 1 },
        response.parsed_body.dig("meta", "pagination"))
    end
  end

  test "authorization verification is inherited" do
    with_probe_routes do
      assert_raises(Pundit::AuthorizationNotPerformedError) { get "/probe/missing_authorization?displayName=ok" }
    end
  end

  test "authentication seam refuses missing and arbitrary bearer tokens" do
    with_probe_routes do
      [ nil, "Bearer arbitrary-token", "Basic credentials" ].each do |header|
        get "/protected", headers: { "Authorization" => header }
        assert_response :unauthorized
        assert_equal "unauthorized", response.parsed_body.dig("error", "code")
      end
    end
  end

  private

  def with_probe_routes(&block)
    with_routing do |routes|
      routes.draw do
        match "/probe/:kind", to: "boundary_probe#show", via: %i[get post]
        get "/protected", to: "protected_probe#show"
      end
      instance_exec(&block)
    end
  end
end
