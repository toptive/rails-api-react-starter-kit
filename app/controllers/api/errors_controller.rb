module Api
  class ErrorsController < ApplicationController
    def show
      skip_authorization
      render_api_error(ApiError.for_unmatched_route(request))
    end
  end
end
