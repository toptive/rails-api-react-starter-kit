module Api
  module V1
    module Settings
      class EmailPreferencesController < BaseController
        def show
          authorize current_user
          render_data(current_user, serializer: EmailPreferencesSerializer)
        end

        def update
          authorize current_user
          render_data(current_user.update_email_preferences!(params.permit(:optional_emails).to_h.symbolize_keys, current_scope, request),
            serializer: EmailPreferencesSerializer)
        end
      end
    end
  end
end
