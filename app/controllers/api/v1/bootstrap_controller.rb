module Api
  module V1
    class BootstrapController < BaseController
      skip_before_action :authenticate!
      before_action :authenticate_optional!

      def show
        skip_authorization
        render_data(Bootstrap.for_session(current_session, scope: current_scope), serializer: BootstrapSerializer)
      end
    end
  end
end
