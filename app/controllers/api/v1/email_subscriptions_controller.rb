module Api
  module V1
    class EmailSubscriptionsController < BaseController
      skip_before_action :authenticate!

      def show
        skip_authorization
        render_data(EmailSubscription.preview(params[:token]), serializer: EmailSubscriptionSerializer)
      end
    end
  end
end
