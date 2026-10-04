module Api
  module V1
    module Settings
      class BillingsController < BaseController
        def show
          authorize Billing
          render_data(Billing.overview(current_scope), serializer: BillingOverviewSerializer)
        end
      end
    end
  end
end
