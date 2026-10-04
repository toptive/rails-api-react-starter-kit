module Api
  module V1
    module Admin
      class JobsAccessesController < BaseController
        def create
          authorize OperationsAccess
          render_data(OperationsAccess.issue(current_session, request), serializer: JobsAccessSerializer, status: :created)
        end
      end
    end
  end
end
