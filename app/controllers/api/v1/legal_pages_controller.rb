module Api
  module V1
    class LegalPagesController < BaseController
      skip_before_action :authenticate!

      def show
        skip_authorization
        render_legal_page(LegalDocument.public_page(params[:slug], I18n.locale.to_s))
      end
    end
  end
end
