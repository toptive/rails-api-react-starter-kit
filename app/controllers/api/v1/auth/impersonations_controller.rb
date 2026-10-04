module Api
  module V1
    module Auth
      class ImpersonationsController < BaseController
        def destroy
          authorize current_session
          current_session.end_impersonation!(request)
          head :no_content
        end
      end
    end
  end
end
