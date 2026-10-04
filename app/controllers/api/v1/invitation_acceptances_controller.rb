module Api
  module V1
    class InvitationAcceptancesController < BaseController
      def create
        authorize Invitation, :accept?
        render_data(Invitation.accept!(current_scope, params[:invitation_token], request), serializer: MembershipSerializer, status: :created)
      end
    end
  end
end
