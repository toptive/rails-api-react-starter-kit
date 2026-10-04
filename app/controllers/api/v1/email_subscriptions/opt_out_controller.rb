module Api
  module V1
    module EmailSubscriptions
      class OptOutController < BaseController
        skip_before_action :authenticate!
        skip_before_action :require_json_body, if: -> { request.media_type == "application/x-www-form-urlencoded" }
        before_action :validate_one_click_body
        rate_limit to: 120, within: 1.minute, only: :create, store: RATE_LIMIT_STORE, with: :render_rate_limited

        def create
          skip_authorization
          render_email_subscription(EmailSubscription.opt_out!(params[:email_subscription_token], request))
        end

        private

        def validate_one_click_body
          request.media_type != "application/x-www-form-urlencoded" ||
            params["List-Unsubscribe"] == "One-Click" || raise(ApiError.bad_request)
        end

        def render_email_subscription(payload)
          request.media_type == "application/x-www-form-urlencoded" && (return head :ok)
          render_data(payload, serializer: EmailSubscriptionSerializer)
        end
      end
    end
  end
end
