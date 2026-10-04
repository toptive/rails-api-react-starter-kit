module Api
  module V1
    module Admin
      class JobsAccessesController < BaseController
        skip_before_action :authenticate!
        before_action :require_superadmin!

        def create
          authorize current_session, :jobs_access?
          response.headers["Set-Cookie"] = OperationsAccess.issue(current_session)
          head :no_content
        end
      end
    end
  end
end
