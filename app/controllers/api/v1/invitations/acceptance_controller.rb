module Api
  module V1
    module Invitations
      class AcceptanceController < BaseController
        def create
          authorize Invitation, :accept?
          render_data(Invitation.accept!(current_scope, params[:invitation_token], request), serializer: MembershipSerializer, status: :created)
        end
      end
    end
  end
end
