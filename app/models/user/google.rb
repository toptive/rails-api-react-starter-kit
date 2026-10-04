require "net/http"

class User::Google
  AUTHORIZE_URL = "https://accounts.google.com/o/oauth2/v2/auth"
  TOKEN_URL = "https://oauth2.googleapis.com/token"
  PROFILE_URL = "https://openidconnect.googleapis.com/v1/userinfo"

  def start(attributes)
    raise ApiError.not_found unless User.google_enabled?

    path = attributes[:return_to].to_s
    path = nil unless path.start_with?("/") && !path.include?("//") && !path.include?("\\") && path.length <= 200
    state = verifier.generate({ nonce: SecureRandom.urlsafe_base64(24), client: attributes[:client] == "native" ? "native" : "web",
      returnTo: path, locale: I18n.locale.to_s, iat: Time.current.to_i }, expires_in: 10.minutes)
    "#{AUTHORIZE_URL}?#{URI.encode_www_form(client_id: ENV.fetch("GOOGLE_CLIENT_ID"), redirect_uri: callback_url,
      response_type: "code", scope: "openid email profile", prompt: "select_account", state: state)}"
  end

  def callback(attributes, request)
    raise ApiError.not_found unless User.google_enabled?

    state = verifier.verified(attributes[:state].to_s)&.symbolize_keys
    return handoff({ client: "web" }, error: "state_invalid") unless state

    raise ApiError.unprocessable(:oauth_failed) if attributes[:error].present? || attributes[:code].blank?

    token = http(TOKEN_URL, form: { code: attributes[:code], client_id: ENV.fetch("GOOGLE_CLIENT_ID"),
      client_secret: ENV.fetch("GOOGLE_CLIENT_SECRET"), redirect_uri: callback_url, grant_type: "authorization_code" })
    profile = http(PROFILE_URL, bearer: token.fetch("access_token"))
    raise ApiError.unprocessable(:email_not_verified) unless profile["email_verified"] == true
    raise ApiError.unprocessable(:oauth_failed) unless profile["sub"].is_a?(String) && profile["sub"].present? && profile["email"].is_a?(String)

    user, created = account(profile, state, request)
    session = user.start_session!(request, method: "google", new_account: created)
    handoff(state, token: session.fetch(:token), expiresAt: session.fetch(:expires_at).utc.iso8601,
      new: created ? "1" : "0", returnTo: state[:returnTo])
  rescue ApiError => error
    raise unless state

    handoff(state, error: error.code)
  rescue KeyError, JSON::ParserError, SocketError, Timeout::Error, IOError, SystemCallError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    state ? handoff(state, error: "oauth_failed") : raise(ApiError.unprocessable(:oauth_failed))
  end

  private

  def verifier
    ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key("google_oauth", 32),
      digest: "SHA256", serializer: JSON, url_safe: true)
  end
  def callback_url = "#{Rails.application.config.x.api_origin}/api/v1/auth/google/callback"

  def http(url, form: nil, bearer: nil)
    uri = URI(url)
    request = form ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
    request.set_form_data(form) if form
    request["Authorization"] = "Bearer #{bearer}" if bearer
    result = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |client| client.request(request) }
    raise ApiError.unprocessable(:oauth_failed) unless result.is_a?(Net::HTTPSuccess)

    JSON.parse(result.body)
  end

  def account(profile, state, request)
    User.transaction do
      user = User.find_by(google_uid: profile["sub"]) || User.find_by(email: profile.fetch("email").downcase)
      unless user
        raise ApiError.unprocessable(:signup_closed) if User.signup_mode == "closed"
        raise ApiError.unprocessable(:invitation_required) if User.signup_mode == "invite" && !Invitation.open_for_email?(profile.fetch("email"))

        user = User.new(name: profile["name"].presence || profile.fetch("email"), email: profile.fetch("email"), locale: state[:locale])
      end
      created = user.new_record?
      user.update!(google_uid: profile.fetch("sub"), confirmed_at: user.confirmed_at || Time.current)
      if created
        Audit.record("user.registered", actor: user, subject: user, metadata: { via: "google", accepted: [] }, request: request)
        ActiveRecord.after_all_transactions_commit { Analytics.track("user_registered", user_id: user.id, via: "google") }
      end
      [ user, created ]
    end
  end

  def handoff(state, **fragment)
    base = if state[:client] == "native"
      scheme = ENV.fetch("NATIVE_SCHEME", "starterkit")
      raise ApiError.unprocessable(:oauth_failed) unless scheme.match?(/\A[a-z][a-z0-9+.-]*\z/)

      "#{scheme}://auth/callback"
    else
      "#{ENV['PUBLIC_URL'].presence || Rails.application.config.x.spa_origin}/auth/callback"
    end
    "#{base}##{URI.encode_www_form(fragment.compact)}"
  end
end
