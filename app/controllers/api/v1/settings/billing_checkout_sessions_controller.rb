module Api
  module V1
    module Settings
      class BillingCheckoutSessionsController < BaseController
        before_action :require_billing!
        def create
          authorize Billing
          attributes = params.permit(:offer_id, :offer_revision, :accepted).to_h.symbolize_keys
          render_data(Billing.checkout(current_scope, attributes, request), serializer: RedirectUrlSerializer, status: :created)
        end

        private

        def require_billing!
          Billing.require_enabled!
        end
      end
    end
  end
end
