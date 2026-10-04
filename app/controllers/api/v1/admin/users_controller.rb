module Api
  module V1
    module Admin
      class UsersController < BaseController
        def index
          authorize User, policy_class: AdminUserPolicy
          render_collection(User.admin_list(search_query), serializer: UserSerializer)
        end

        def show
          authorize User, policy_class: AdminUserPolicy
          render_data(User.admin_detail(params[:id]), serializer: AdminUserDetailSerializer)
        end

        def update
          authorize User, policy_class: AdminUserPolicy
          render_data(User.admin_update!(params[:id], cast_string_attributes(:role), current_scope, request), serializer: UserSerializer)
        end
      end
    end
  end
end
