module Api
  module V1
    class OrganizationsController < BaseController
      def create
        authorize Organization
        attributes = cast_string_attributes(:name)
        render_data(Organization.create_current!(current_scope, attributes, request), serializer: OrganizationSerializer, status: :created)
      end
    end
  end
end
