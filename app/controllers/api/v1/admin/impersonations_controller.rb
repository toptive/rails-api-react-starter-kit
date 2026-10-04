module Api
  module V1
    module Admin
      class ImpersonationsController < BaseController
        def create
          authorize Impersonation
          render_data(Impersonation.start!(current_scope, params[:user_id], cast_string_attributes(:reason), request), serializer: AuthSessionSerializer, status: :created)
        end
      end
    end
  end
end
