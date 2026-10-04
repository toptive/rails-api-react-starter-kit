module Api
  module V1
    module Settings
      class OrganizationsController < BaseController
        def show
          authorize current_scope.organization
          render_data(Organization.settings(current_scope), serializer: OrganizationSettingsSerializer)
        end

        def update
          authorize current_scope.organization
          attributes = cast_string_attributes(:name)
          render_data(Organization.update_current!(current_scope, attributes, request), serializer: OrganizationSerializer)
        end
      end
    end
  end
end
