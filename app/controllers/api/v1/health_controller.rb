module Api
  module V1
    class HealthController < BaseController
      skip_before_action :authenticate!

      def show
        skip_authorization
        response.headers["Cache-Control"] = "no-store"
        render_data({ status: "ok" }, serializer: HealthSerializer)
      end
    end
  end
end
