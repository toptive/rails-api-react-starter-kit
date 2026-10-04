module Api
  module V1
    module Settings
      class InvitationsController < BaseController
        rate_limit to: 30, within: 1.hour, only: :create, store: RATE_LIMIT_STORE, with: :render_rate_limited

        def index
          authorize Invitation
          render_data(Invitation.list(current_scope), serializer: InvitationSerializer)
        end

        def create
          authorize Invitation
          attributes = cast_string_attributes(:email, :role, :access)
          render_data(Invitation.issue!(current_scope, attributes, request), serializer: InvitationSerializer, status: :created)
        end

        def destroy
          authorize Invitation
          Invitation.revoke!(current_scope, params[:id], request)
          head :no_content
        end
      end
    end
  end
end
