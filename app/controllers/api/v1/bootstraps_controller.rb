module Api
  module V1
    class BootstrapsController < BaseController
      skip_before_action :authenticate!

      def show
        skip_authorization
        render_data(Bootstrap.for_session(current_session), serializer: BootstrapSerializer)
      end
    end
  end
end
