require "test_helper"
require_relative "../support/admin_requests"

class SeoTest < ActionDispatch::IntegrationTest
  include AdminRequests

  setup { @saved_public_env = ENV.to_h.slice("PUBLIC_URL", "CANONICAL_HOST") }
  teardown { %w[PUBLIC_URL CANONICAL_HOST].each { |name| ENV[name] = @saved_public_env[name] } }

  test "sitemap lists every public page in every locale and published legal documents only" do
    ENV["PUBLIC_URL"] = "https://public.example"
    new_legal_version("terms", publish: true)
    new_legal_version("privacy", publish: false)
    get "/sitemap.xml"
    assert_response :ok
    assert_equal "application/xml", response.media_type
    xml = Nokogiri::XML(response.body)
    namespaces = { "s" => "http://www.sitemaps.org/schemas/sitemap/0.9", "x" => "http://www.w3.org/1999/xhtml" }
    assert_equal [ "https://public.example/", "https://public.example/es", "https://public.example/legal/terms",
      "https://public.example/es/legal/terms" ], xml.xpath("//s:loc", namespaces).map(&:text)
    xml.xpath("//s:url", namespaces).each do |url|
      alternates = url.xpath("x:link", namespaces)
      assert_equal %w[en es], alternates.map { |link| link["hreflang"] }
      assert alternates.all? { |link| link["rel"] == "alternate" }
    end
    refute_includes response.body, "privacy"
  end

  test "robots repeat private routes for every allowed search and training crawler in every locale" do
    ENV["PUBLIC_URL"] = "https://public.example"
    get "/robots.txt"
    assert_response :ok
    assert_equal "text/plain", response.media_type
    groups = response.body.split("\n\n")
    [ "*", *Seo::SEARCH_BOTS, *Seo::TRAINING_BOTS ].each do |bot|
      group = groups.find { |item| item.start_with?("User-agent: #{bot}\n") }
      assert group, bot
      group += "\n"
      assert_includes group, "Allow: /\n"
      %w[/admin /api /dashboard /onboarding /settings /session /registration /magic-links /invitations
        /auth /email-subscriptions /organizations /sudo/new /session/check-your-email /errors/403 /errors/404 /errors/500].each do |path|
        assert_includes group, "Disallow: #{path}\n"
        assert_includes group, "Disallow: /es#{path}\n"
      end
    end
    assert response.body.end_with?("Sitemap: https://public.example/sitemap.xml\n")
  end

  test "unapproved training bots are denied without affecting search" do
    previous = Rails.application.config.x.allowed_training_bots
    Rails.application.config.x.allowed_training_bots = [ "GPTBot" ]
    get "/robots.txt"
    assert_includes response.body, "User-agent: ClaudeBot\nDisallow: /\n"
    assert_includes response.body, "User-agent: GPTBot\nAllow: /\n"
    assert_includes response.body, "User-agent: Googlebot\nAllow: /\n"
  ensure
    Rails.application.config.x.allowed_training_bots = previous
  end

  test "indexing lock empties sitemap disallows everything and covers API static assets and errors" do
    Flags.with(:site_indexing, false) do
      get "/sitemap.xml"
      assert_response :ok
      assert_empty Nokogiri::XML(response.body).xpath("//*[local-name()='url']")
      assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
      get "/robots.txt"
      assert_includes response.body, "User-agent: *\nDisallow: /\n"
      refute_includes response.body, "Allow: /"
      [ "/api/v1/bootstrap", "/api/v1/missing", "/favicon.ico" ].each do |path|
        get path
        assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
      end
    end
  end

  test "canonical public host keeps path and query and uses permanent method appropriate redirects" do
    ENV["CANONICAL_HOST"] = "public.example"
    ENV["PUBLIC_URL"] = "https://public.example"
    get "/legal/terms?locale=es", headers: { "Host" => "www.public.example" }
    assert_response :moved_permanently
    assert_equal "https://public.example/legal/terms?locale=es", response.headers["Location"]
    post "/api/v1/events", params: { name: "page_viewed" }, headers: { "Host" => "old.example" }, as: :json
    assert_response :permanent_redirect
    assert_equal "https://public.example/api/v1/events", response.headers["Location"]
    get "/health", headers: { "Host" => "old.example" }
    assert_response :ok
    assert_nil response.headers["Location"]
    get "/api/v1/bootstrap", headers: { "Host" => URI(Rails.application.config.x.api_origin).host }
    assert_response :ok
    get "/robots.txt", headers: { "Host" => "public.example" }
    assert_response :ok
  end
end
