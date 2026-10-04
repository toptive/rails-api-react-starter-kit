module Jobs
  class SessionsController < ApplicationController
    def show
      skip_authorization
      response.headers["Set-Cookie"] = OperationsAccess.exchange(params[:ticket])
      redirect_to "/jobs", status: :found
    end
  end
end
