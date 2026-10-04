module Api
  module V1
    module Settings
      class SessionsController < BaseController
        def index
          authorize current_user, :show?
          render_data(Session.devices_for(current_user), serializer: SessionSerializer,
            serializer_params: { current_session_id: current_session.id })
        end

        def destroy
          authorize current_user, :update?
          Session.revoke_device!(current_user, params[:id], request)
          head :no_content
        end
      end
    end
  end
end
