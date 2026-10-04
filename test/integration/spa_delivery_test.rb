require "test_helper"
require "tmpdir"

class SpaDeliveryTest < ActionDispatch::IntegrationTest
  setup do
    @public = Dir.mktmpdir("rails-spa-test")
    @previous = Rails.application.config.x.spa_public_directory
    Rails.application.config.x.spa_public_directory = @public
    File.write(File.join(@public, "index.html"), '<html><script data-bootstrap>boot()</script><script type="module" src="/assets/app-123.js"></script><script type="application/ld+json">{}</script><body>Root SPA</body></html>')
    FileUtils.mkdir_p(File.join(@public, "es/legal/terms"))
    File.write(File.join(@public, "es/legal/terms/index.html"), "<html><script data-bootstrap>boot()</script><body>Published Spanish terms</body></html>")
  end

  teardown do
    Rails.application.config.x.spa_public_directory = @previous
    FileUtils.remove_entry(@public)
  end

  test "browser routes receive HTML with fresh bootstrap-only CSP nonces" do
    get "/dashboard"
    assert_response :ok
    assert_equal "text/html", response.media_type
    assert_includes response.body, "Root SPA"
    first = response.body[/nonce="([^"]+)"/, 1]
    assert first
    assert_includes response.headers.fetch("Content-Security-Policy"), "'nonce-#{first}'"
    assert_equal 1, response.body.scan("nonce=").size
    assert_equal "private, no-store", response.headers.fetch("Cache-Control")
    get "/unknown/browser/path"
    assert_response :ok
    refute_equal first, response.body[/nonce="([^"]+)"/, 1]
    get "/unknown/browser.path"
    assert_response :ok
    assert_includes response.body, "Root SPA"
    head "/dashboard"
    assert_response :ok
    assert_empty response.body
  end

  test "prerendered legal pages win and other paths retain the root fallback" do
    get "/es/legal/terms"
    assert_includes response.body, "Published Spanish terms"
    get "/legal/privacy"
    assert_includes response.body, "Root SPA"
    get "/api/v1/unknown"
    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")
    get "/api/unknown"
    assert_response :not_found
    get "/health"
    assert_equal "text/plain", response.media_type
    get "/robots.txt"
    assert_equal "text/plain", response.media_type
    get "/sitemap.xml"
    assert_equal "application/xml", response.media_type
    get "/admin/jobs/unknown"
    assert_response :not_found
    refute_includes response.body, "Root SPA"
  end

  test "hashed assets use immutable cache headers through the real static server" do
    asset = "spa-test-#{SecureRandom.hex(8)}.js"
    path = Rails.public_path.join("assets", asset)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "export const ready = true")
    get "/assets/#{asset}"
    assert_response :ok
    assert_includes response.headers.fetch("Cache-Control"), "max-age=31536000, immutable"
  ensure
    FileUtils.rm_f(path) if path
  end
end
