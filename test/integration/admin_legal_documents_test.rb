require "test_helper"
require_relative "../support/admin_requests"

class AdminLegalDocumentsTest < ActionDispatch::IntegrationTest
  include AdminRequests

  test "legal index creates the three documents on demand and orders versions newest first" do
    assert_difference "LegalDocument.count", 3 do
      get "/api/v1/admin/legal-documents", headers: admin_headers
      assert_response :ok
    end
    assert_equal %w[cookies privacy terms], data.map { |document| document.fetch("slug") }
    assert data.all? { |document| document.fetch("versions").empty? && document.fetch("publishedVersionId").nil? }
    first = new_legal_version("terms")
    second = new_legal_version("terms", note: "Revised wording")
    get "/api/v1/admin/legal-documents/terms", headers: admin_headers
    assert_response :ok
    assert_equal [ second.fetch("id"), first.fetch("id") ], data.fetch("versions").map { |version| version.fetch("id") }
    assert_equal "Revised wording", data.fetch("versions").first.fetch("note")
    assert_nil data.fetch("publishedVersionId")
    assert_no_difference "LegalDocument.count" do
      get "/api/v1/admin/legal-documents", headers: admin_headers
      assert_response :ok
    end
    get "/api/v1/admin/legal-documents/unknown", headers: admin_headers
    assert_error :not_found, "not_found"
  end

  test "version creation can publish atomically and audits both actions" do
    version = new_legal_version("privacy", publish: true, titles: { en: "Privacy", es: "Privacidad" }, bodies: { en: "English", es: "Español" })
    assert_equal 1, version.fetch("number")
    assert version.fetch("publishedAt").end_with?("Z")
    assert version.fetch("insertedAt").end_with?("Z")
    assert_equal({ "en" => "Privacy", "es" => "Privacidad" }, version.fetch("titles"))
    assert_equal @admin.id, LegalDocumentVersion.find(version.fetch("id")).created_by_id
    assert_equal version.fetch("id"), LegalDocument.find_by!(slug: "privacy").published_version_id
    %w[legal.version_created legal.published].each do |action|
      event = AuditEvent.find_by!(action: action, subject_id: version.fetch("id"))
      assert_equal @admin.id, event.actor_id
      assert_equal({ "slug" => "privacy", "number" => 1 }, event.metadata)
    end
  end

  test "publication makes a draft public and repeated publication is idempotent" do
    draft = new_legal_version("terms")
    get "/api/v1/legal-pages/terms"
    assert_error :not_found, "not_found"
    post "/api/v1/admin/legal-documents/terms/versions/1/publication", headers: admin_headers, as: :json
    assert_response :created
    assert_equal draft.fetch("id"), data.fetch("publishedVersionId")
    published_at = data.fetch("versions").first.fetch("publishedAt")
    assert_no_difference "AuditEvent.count" do
      post "/api/v1/admin/legal-documents/terms/versions/1/publication", headers: admin_headers, as: :json
      assert_response :created
    end
    assert_equal published_at, data.fetch("versions").first.fetch("publishedAt")
    [ "0", "missing", "99" ].each do |number|
      post "/api/v1/admin/legal-documents/terms/versions/#{number}/publication", headers: admin_headers, as: :json
      assert_error :not_found, "not_found"
    end
    post "/api/v1/admin/legal-documents/unknown/versions/1/publication", headers: admin_headers, as: :json
    assert_error :not_found, "not_found"
  end

  test "version fields require English and validate locale values size caps note and publish types" do
    [ [ :titles, {} ], [ :titles, { en: "" } ], [ :bodies, { es: "Texto" } ], [ :bodies, nil ] ].each do |field, value|
      post_version(field => value)
      assert_admin_field field.to_s, "validation.english_required"
    end
    [ [ :titles, { en: "a" * 256 }, 255 ], [ :bodies, { en: "a" * 100_001 }, 100_000 ], [ :note, "a" * 256, 255 ] ].each do |field, value, count|
      assert_no_difference [ "LegalDocumentVersion.count", "AuditEvent.count" ] do
        post_version(field => value, publish: true)
      end
      assert_admin_field field.to_s, "validation.length_max", bindings: { "count" => count }
    end
    [ [ :titles, { en: "Title", es: 42 } ], [ :bodies, { en: "Body", fr: "Unsupported" } ] ].each do |field, value|
      post_version(field => value)
      assert_admin_field field.to_s, "validation.cast"
    end
    [ { publish: "bad" }, { publish: 42 }, { note: 42 } ].each do |attributes|
      post_version(attributes)
      assert_error :bad_request, "bad_request"
    end
    post "/api/v1/admin/legal-documents/unknown/versions", params: { titles: { en: "Title" }, bodies: { en: "Body" } }, headers: admin_headers, as: :json
    assert_error :not_found, "not_found"
    post "/api/v1/admin/legal-documents/terms/versions", params: {}, headers: admin_headers, as: :json
    assert_admin_field "titles", "validation.english_required"
    new_legal_version("terms", titles: { en: "a" * 255 }, bodies: { en: "a" * 100_000 }, note: "a" * 255)
  end

  private

  def post_version(attributes)
    post "/api/v1/admin/legal-documents/terms/versions", params: {
      titles: { en: "Title" }, bodies: { en: "Body" }
    }.merge(attributes), headers: admin_headers, as: :json
  end
end
