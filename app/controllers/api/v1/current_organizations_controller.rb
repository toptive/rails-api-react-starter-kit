module Api
  module V1
    class CurrentOrganizationsController < BaseController
      def update
        authorize Organization, :switch?
        attributes = cast_string_attributes(:organization_id)
        render_data(Organization.switch_current!(current_scope, attributes), serializer: AuthSerializer)
      end
    end
  end
end
