module Api
  module V1
    module Settings
      class AccountController < BaseController
        before_action :require_sudo!
        rate_limit to: 5, within: 1.minute, only: :destroy, store: RATE_LIMIT_STORE, with: :render_rate_limited

        def show
          authorize current_user
          render_data(AccountDeletion.preview(current_scope), serializer: AccountDeletionSerializer)
        end

        def destroy
          authorize current_user
          AccountDeletion.delete!(current_scope, request)
          head :no_content
        end
      end
    end
  end
end
