require_relative "auth_requests"

module AdminRequests
  extend ActiveSupport::Concern
  include AuthRequests

  included do
    setup do
      @admin = create_user(role: "superadmin")
      @admin_token = sign_in(@admin)
    end
  end

  def admin_headers = bearer(@admin_token)

  def assert_admin_field(field, key, bindings: nil)
    assert_error :unprocessable_entity, "validation_failed"
    detail = response.parsed_body.dig("error", "details", field, 0)
    assert_equal key, detail.fetch("key")
    assert_equal I18n.t(key, **(bindings || {}).symbolize_keys), detail.fetch("message")
    bindings ? assert_equal(bindings, detail["bindings"]) : assert_nil(detail["bindings"])
  end

  def new_legal_version(slug, publish: false, **attributes)
    post "/api/v1/admin/legal-documents/#{slug}/versions", params: {
      titles: { en: "#{slug.capitalize} title", es: "Título" }, bodies: { en: "## Heading\n\nPlain body", es: "Texto" }, publish: publish
    }.merge(attributes), headers: admin_headers, as: :json
    assert_response :created
    data
  end
end
