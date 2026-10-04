module Api
  class ExceptionsController < ApplicationController
    def show
      skip_authorization
      render_api_error(ApiException.from_request(request))
    end
  end
end
