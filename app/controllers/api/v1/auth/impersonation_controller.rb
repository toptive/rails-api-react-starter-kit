module Api
  module V1
    module Auth
      class ImpersonationController < BaseController
        def destroy
          authorize current_session
          current_session.end_impersonation!(request)
          head :no_content
        end
      end
    end
  end
end
