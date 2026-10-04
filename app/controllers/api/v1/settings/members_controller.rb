module Api
  module V1
    module Settings
      class MembersController < BaseController
        def index
          authorize Membership
          render_data(Membership.list(current_scope), serializer: MembershipSerializer)
        end

        def update
          authorize Membership
          attributes = cast_string_attributes(:role, :access)
          render_data(Membership.update_member!(current_scope, params[:id], attributes, request), serializer: MembershipSerializer)
        end

        def destroy
          authorize Membership
          Membership.remove_member!(current_scope, params[:id], request)
          head :no_content
        end
      end
    end
  end
end
