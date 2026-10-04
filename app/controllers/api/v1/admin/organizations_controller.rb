module Api
  module V1
    module Admin
      class OrganizationsController < BaseController
        def index
          authorize Organization, policy_class: AdminOrganizationPolicy
          render_collection(Organization.admin_list(search_query), serializer: AdminOrganizationSerializer)
        end

        def show
          authorize Organization, policy_class: AdminOrganizationPolicy
          render_data(Organization.admin_detail(params[:id]), serializer: AdminOrganizationDetailSerializer)
        end
      end
    end
  end
end
