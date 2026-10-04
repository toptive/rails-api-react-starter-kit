module Webhooks
  module Stripe
    class EventsController < ApplicationController
      skip_around_action :switch_locale
      skip_before_action :normalize_param_keys
      rate_limit to: 600, within: 1.minute, store: Api::V1::BaseController::RATE_LIMIT_STORE, with: :render_rate_limited

      def create
        skip_authorization
        render_webhook_receipt(Billing.receive(request.raw_post, request.headers["Stripe-Signature"]))
      end
    end
  end
end
