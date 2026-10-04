module Api
  module V1
    module Settings
      class PasswordsController < BaseController
        before_action :require_sudo!

        def update
          authorize current_user
          render_data(current_user.update_password!(cast_string_attributes(:password, :password_confirmation), current_scope, request),
            serializer: AuthSessionSerializer)
        end
      end
    end
  end
end
