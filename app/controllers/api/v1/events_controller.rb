module Api
  module V1
    class EventsController < BaseController
      skip_before_action :authenticate!
      rate_limit to: 120, within: 1.minute, store: RATE_LIMIT_STORE, with: :render_rate_limited

      def create
        skip_authorization
        render_data(Analytics.receive({ name: params[:name], properties: params[:properties] }, current_session),
          serializer: EventReceiptSerializer, status: :accepted)
      end
    end
  end
end
