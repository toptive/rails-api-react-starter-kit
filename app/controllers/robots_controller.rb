class RobotsController < ApplicationController
  def show
    skip_authorization
    render plain: Seo.robots, content_type: "text/plain"
  end
end
