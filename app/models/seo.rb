class Seo
  SEARCH_BOTS = %w[Googlebot Bingbot OAI-SearchBot ChatGPT-User Claude-SearchBot Claude-User PerplexityBot Perplexity-User].freeze
  TRAINING_BOTS = %w[GPTBot ClaudeBot Google-Extended CCBot].freeze
  PRIVATE_PATHS = %w[/admin /api /dashboard /onboarding /settings /session /registration /magic-links
    /invitations /auth /email-subscriptions /organizations /sudo/new /session/check-your-email /errors/403 /errors/404 /errors/500].freeze

  def self.sitemap
    locales = TranslationCatalog.locales
    paths = Flags.enabled?(:site_indexing) ? [ "/", *LegalDocument.where.not(published_version_id: nil).order(:slug).pluck(:slug).map { |slug| "/legal/#{slug}" } ] : []
    urls = paths.flat_map do |path|
      alternates = locales.map do |locale|
        %(<xhtml:link rel="alternate" hreflang="#{locale}" href="#{CGI.escapeHTML(localized_url(path, locale))}"/>)
      end.join
      locales.map { |locale| "<url><loc>#{CGI.escapeHTML(localized_url(path, locale))}</loc>#{alternates}</url>" }
    end.join
    %(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">#{urls}</urlset>)
  end

  def self.localized_url(path, locale)
    prefix = locale == TranslationCatalog.locales.first ? "" : "/#{locale}"
    suffix = path == "/" && prefix.present? ? "" : path
    "#{Billing.public_url}#{prefix}#{suffix}"
  end
  private_class_method :localized_url

  def self.robots
    groups = if Flags.enabled?(:site_indexing)
      configured = Rails.application.config.x.allowed_training_bots
      allowed = configured.is_a?(Array) ? configured : TRAINING_BOTS
      ([ "*" ] + SEARCH_BOTS).map { |bot| group(bot, true) } + TRAINING_BOTS.map { |bot| group(bot, allowed.include?(bot)) }
    else
      [ group("*", false) ]
    end
    groups.join("\n") + "\nSitemap: #{Billing.public_url}/sitemap.xml\n"
  end

  def self.group(agent, allowed)
    return "User-agent: #{agent}\nDisallow: /\n" unless allowed

    paths = PRIVATE_PATHS + TranslationCatalog.locales.flat_map { |locale| PRIVATE_PATHS.map { |path| "/#{locale}#{path}" } }
    "User-agent: #{agent}\nAllow: /\n" + paths.map { |path| "Disallow: #{path}\n" }.join
  end
  private_class_method :group
end
