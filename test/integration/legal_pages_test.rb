require "test_helper"
require_relative "../support/admin_requests"

class LegalPagesTest < ActionDispatch::IntegrationTest
  include AdminRequests

  test "public page uses the request locale with English fallback independently for each field" do
    new_legal_version("terms", publish: true, titles: { en: "Terms", es: "Condiciones" }, bodies: { en: "## Heading\n\nPlain <text>", es: "" })
    get "/api/v1/legal-pages/terms", headers: { "Accept-Language" => "es-AR" }
    assert_response :ok
    assert_equal({ "slug" => "terms", "title" => "Condiciones", "body" => "## Heading\n\nPlain <text>",
      "version" => 1, "publishedAt" => LegalDocument.find_by!(slug: "terms").published_version.published_at.utc.iso8601 }, data)
    assert_equal '"terms:1:es"', response.headers["ETag"]
    assert_equal "public, no-cache", response.headers["Cache-Control"]
    get "/api/v1/legal-pages/terms?locale=en", headers: { "Accept-Language" => "es" }
    assert_equal "Terms", data.fetch("title")
    assert_equal '"terms:1:en"', response.headers["ETag"]
    new_legal_version("privacy", publish: true, titles: { en: "Privacy" }, bodies: { en: "English", es: "Español" })
    get "/api/v1/legal-pages/privacy?locale=es"
    assert_equal "Privacy", data.fetch("title")
    assert_equal "Español", data.fetch("body")
  end

  test "publishing a newer version changes the public page and its ETag flow" do
    new_legal_version("terms", publish: true)
    get "/api/v1/legal-pages/terms"
    original_etag = response.headers.fetch("ETag")
    get "/api/v1/legal-pages/terms", headers: { "If-None-Match" => original_etag }
    assert_response :not_modified
    assert_empty response.body
    assert_equal "public, no-cache", response.headers["Cache-Control"]
    draft = new_legal_version("terms", bodies: { en: "New text" })
    get "/api/v1/legal-pages/terms", headers: { "If-None-Match" => original_etag }
    assert_response :not_modified
    post "/api/v1/admin/legal-documents/terms/versions/#{draft.fetch('number')}/publication", headers: admin_headers, as: :json
    assert_response :created
    get "/api/v1/legal-pages/terms", headers: { "If-None-Match" => original_etag }
    assert_response :ok
    assert_equal "New text", data.fetch("body")
    assert_equal 2, data.fetch("version")
    assert_equal '"terms:2:en"', response.headers["ETag"]
    refute_equal original_etag, response.headers["ETag"]
  end

  test "unknown and unpublished pages return 404" do
    new_legal_version("cookies")
    %w[cookies unknown privacy].each do |slug|
      get "/api/v1/legal-pages/#{slug}"
      assert_error :not_found, "not_found"
    end
  end

  test "registration records the exact published terms and privacy versions and retains consent after deletion" do
    terms = new_legal_version("terms", publish: true)
    privacy = new_legal_version("privacy", publish: true)
    new_legal_version("terms")
    new_legal_version("cookies", publish: true)
    post "/api/v1/auth/registrations", params: { name: "New user", email: "new@example.com", termsAccepted: true }, as: :json
    assert_response :accepted
    user = User.find_by!(email: "new@example.com")
    assert_equal({ "terms" => 1, "privacy" => 1 }, user.legal_accepted_versions)
    accepted = LegalAcceptance.where(user: user).order(:id).to_a
    assert_equal [ terms.fetch("id"), privacy.fetch("id") ].sort, accepted.map(&:legal_document_version_id).sort
    assert accepted.all? { |row| row.ip_address == "127.0.0.1" && row.email_hash == Digest::SHA256.hexdigest(user.email) }
    event = AuditEvent.find_by!(action: "user.registered", subject_id: user.id)
    assert_equal %w[privacy terms], event.metadata.fetch("accepted").sort
    user.destroy!
    accepted.each do |row|
      assert_nil row.reload.user_id
      assert row.legal_document_version
    end
  end

  test "registration refuses unchecked consent before recording any acceptance" do
    new_legal_version("terms", publish: true)
    assert_no_difference [ "User.count", "LegalAcceptance.count", "AuditEvent.count" ] do
      post "/api/v1/auth/registrations", params: { name: "New user", email: "new@example.com", termsAccepted: false }, as: :json
    end
    assert_admin_field "termsAccepted", "validation.terms_required"
  end
end
