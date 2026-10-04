module Api
  module V1
    module Settings
      class BillingPortalSessionsController < BaseController
        def create
          authorize Billing
          render_data(Billing.portal(current_scope, request), serializer: RedirectUrlSerializer, status: :created)
        end
      end
    end
  end
end
