# HTML is handled before Rails' static server so every bootstrap has a fresh nonce.
class SpaDelivery
  EXCLUDED = %r{\A/(?:api(?:/|\z)|admin/jobs(?:/|\z)|health\z|sitemap\.xml\z|robots\.txt\z|up\z|webhooks(?:/|\z)|dev(?:/|\z))}

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    return @app.call(env) unless %w[GET HEAD].include?(request.request_method) && !request.path.match?(EXCLUDED)
    configured = Rails.application.config.x.spa_public_directory
    root = configured.is_a?(String) ? configured : Rails.public_path
    return @app.call(env) unless root

    static = File.expand_path(request.path.delete_prefix("/"), root)
    return @app.call(env) if request.path.start_with?("/assets/") ||
      (static.start_with?("#{root}/") && File.file?(static) && File.extname(static) != ".html")

    page = public_page(root, request.path)
    return @app.call(env) unless File.file?(page)

    nonce = SecureRandom.base64(24)
    html = File.read(page).sub(/<script\b([^>]*\bdata-bootstrap\b[^>]*)>/, %(<script\\1 nonce="#{nonce}">))
    headers = { "content-type" => "text/html; charset=utf-8", "cache-control" => "private, no-store",
      "content-security-policy" => policy(nonce), "x-content-type-options" => "nosniff" }
    [ 200, headers, request.head? ? [] : [ html ] ]
  end

  private

  def public_page(root, path)
    locales = I18n.available_locales.map { |locale| Regexp.escape(locale.to_s) }.join("|")
    public_path = %r{\A/(?:(?:#{locales})(?:/legal/(?:terms|privacy|cookies))?|legal/(?:terms|privacy|cookies))/?\z}
    if path.match?(public_path)
      candidate = File.join(root, path.delete_prefix("/"), "index.html")
      return candidate if File.file?(candidate)
    end
    File.join(root, "index.html")
  end

  def policy(nonce)
    api = Rails.application.config.x.api_origin
    "default-src 'self'; script-src 'self' 'nonce-#{nonce}' https://challenges.cloudflare.com; " \
      "style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; " \
      "connect-src 'self' #{api} https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; " \
      "object-src 'none'; base-uri 'self'; frame-ancestors 'none'"
  end
end
