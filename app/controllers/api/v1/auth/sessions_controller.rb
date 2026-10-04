module Api
  module V1
    module Auth
      class SessionsController < BaseController
        skip_before_action :authenticate!, only: :create
        rate_limit to: 10, within: 1.minute, store: RATE_LIMIT_STORE, only: :create, with: :render_rate_limited

        def create
          skip_authorization
          render_data(User.sign_in_password(params.permit(:email, :password).to_h.symbolize_keys, request,
            existing_session: current_session), serializer: AuthSessionSerializer, status: :created)
        end

        def destroy
          authorize current_session
          current_session.sign_out!(request)
          head :no_content
        end
      end
    end
  end
end
