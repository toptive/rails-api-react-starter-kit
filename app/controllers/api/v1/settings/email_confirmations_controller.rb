module Api
  module V1
    module Settings
      class EmailConfirmationsController < BaseController
        rate_limit to: 10, within: 1.minute, only: :create, store: RATE_LIMIT_STORE, with: :render_rate_limited

        def show
          authorize current_user, :update?
          render_data(UserToken.peek_email_change(current_user, params[:token]), serializer: EmailChangeSerializer)
        end

        def create
          authorize current_user, :update?
          render_data(current_user.confirm_email!(params[:token], current_scope, request), serializer: UserSerializer)
        end
      end
    end
  end
end
