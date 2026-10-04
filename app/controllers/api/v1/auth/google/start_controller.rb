module Api
  module V1
    module Auth
      module Google
        class StartController < BaseController
          skip_before_action :authenticate!
          rate_limit to: 10, within: 1.minute, store: RATE_LIMIT_STORE, with: :render_rate_limited

          def show
            skip_authorization
            render_oauth_redirect User.google_authorization_url(cast_string_attributes(:client, :return_to))
          end
        end
      end
    end
  end
end
