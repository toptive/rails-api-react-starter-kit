module Api
  module V1
    class InvitationsController < BaseController
      skip_before_action :authenticate!

      def show
        skip_authorization
        render_data(Invitation.preview(params[:token], current_user), serializer: InvitationPreviewSerializer)
      end
    end
  end
end
