module Api
  class ErrorsController < ApplicationController
    def show
      skip_authorization
      render_api_error(ApiError.not_found)
    end
  end
end
