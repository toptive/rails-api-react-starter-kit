require "test_helper"

class LocalesTest < ActionDispatch::IntegrationTest
  test "locale dictionaries keep dotted keys and revalidate with strong ETags" do
    get "/api/v1/locales/es"
    assert_response :ok
    body = response.parsed_body
    assert_equal "StarterKit", body.dig("data", "app.name")
    assert_equal "es", body.dig("meta", "locale")
    assert_equal %Q("es:#{body.dig('meta', 'version')}"), response.headers["ETag"]
    assert_equal "public, no-cache", response.headers["Cache-Control"]
    etag = response.headers["ETag"]
    get "/api/v1/locales/es", headers: { "If-None-Match" => etag }
    assert_response :not_modified
    assert_empty response.body
    assert_equal etag, response.headers["ETag"]
    assert_equal "public, no-cache", response.headers["Cache-Control"]
    get "/api/v1/locales/en", headers: { "If-None-Match" => etag }
    assert_response :ok
    refute_equal etag, response.headers["ETag"]
    get "/api/v1/bootstrap"
    assert_equal body.dig("meta", "version"), response.parsed_body.dig("data", "i18nVersion")
  end

  test "unsupported locales return 404" do
    get "/api/v1/locales/fr"
    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")
  end
end
