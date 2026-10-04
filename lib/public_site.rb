# Applies before static assets and error handling so the indexing lock covers both.
class PublicSite
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    target = canonical_target(request)
    response = if target
      [ %w[GET HEAD].include?(request.request_method) ? 301 : 308,
        { "location" => target, "content-type" => "text/plain", "cache-control" => "no-store" }, [] ]
    else
      @app.call(env)
    end
    response[1]["cache-control"] = "public, max-age=31536000, immutable" if request.path.start_with?("/assets/") && response[0] == 200
    response[1]["x-robots-tag"] = "noindex, nofollow" unless indexing?
    response
  end

  private

  def indexing? = Flags.enabled?(:site_indexing)

  def canonical_target(request)
    public_uri = URI(ENV["PUBLIC_URL"].presence || Rails.application.config.x.spa_origin)
    host = ENV["CANONICAL_HOST"].presence || (Rails.env.production? ? public_uri.host : nil)
    return if host.nil? || request.path == "/health"
    return if request.host == host || request.host == URI(Rails.application.config.x.api_origin).host

    public_uri.host = host
    public_uri.path = request.path
    public_uri.query = request.query_string.presence
    public_uri.fragment = nil
    public_uri.to_s
  end
end
