class OperationsBrowserSession
  def initialize(app)
    @app = app
    @dashboard = ActionDispatch::Cookies.new(ActionDispatch::Session::CookieStore.new(app,
      key: "_jobs_ui", path: "/jobs", expire_after: 5.minutes, httponly: true,
      secure: Rails.env.production?, same_site: :strict))
  end

  def call(env)
    if env["PATH_INFO"].match?(%r{\A/jobs(?:/|\z)})
      # The engine temporarily restricts locales to English; preload the shared backend first.
      I18n.backend.eager_load!
      @dashboard.call(env)
    else
      @app.call(env)
    end
  end
end
