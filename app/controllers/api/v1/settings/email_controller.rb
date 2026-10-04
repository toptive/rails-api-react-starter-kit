module Api
  module V1
    module Settings
      class EmailController < BaseController
        before_action :require_sudo!
        rate_limit to: 5, within: 1.minute, by: -> { current_user.id }, store: RATE_LIMIT_STORE, with: :render_rate_limited

        def update
          authorize current_user
          render_data(current_user.request_email_change!(cast_string_attributes(:email)), serializer: EmailChangeSerializer, status: :accepted)
        end
      end
    end
  end
end
