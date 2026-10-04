module Api
  module V1
    module Admin
      class DashboardController < BaseController
        def show
          authorize AdminOverview
          render_data(AdminOverview.stats, serializer: AdminStatsSerializer)
        end
      end
    end
  end
end
