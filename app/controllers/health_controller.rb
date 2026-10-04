class HealthController < ApplicationController
  skip_around_action :switch_locale
  skip_before_action :normalize_param_keys

  def show
    skip_authorization
    result = Health.check
    response.headers["Cache-Control"] = "no-store"
    render plain: result.fetch(:body), status: result.fetch(:status)
  end
end
