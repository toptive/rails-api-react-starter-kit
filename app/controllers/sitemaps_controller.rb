class SitemapsController < ApplicationController
  def show
    skip_authorization
    render plain: Seo.sitemap, content_type: "application/xml"
  end
end
