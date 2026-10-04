module Api
  module V1
    class LocalesController < BaseController
      skip_before_action :authenticate!

      def show
        skip_authorization
        catalogue = TranslationCatalog.for_locale(params[:locale])
        render_catalogue(catalogue)
      end
    end
  end
end
