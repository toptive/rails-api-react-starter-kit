module Api
  module V1
    module Auth
      module Google
        class CallbackController < BaseController
          skip_before_action :authenticate!
          rate_limit to: 20, within: 1.minute, store: RATE_LIMIT_STORE, with: :render_rate_limited

          def show
            skip_authorization
            render_oauth_redirect User.google_callback_url(cast_string_attributes(:state, :code, :error), request)
          end
        end
      end
    end
  end
end
