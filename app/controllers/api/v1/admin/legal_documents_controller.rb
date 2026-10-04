module Api
  module V1
    module Admin
      class LegalDocumentsController < BaseController
        def index
          authorize LegalDocument
          render_data(LegalDocument.admin_list, serializer: LegalDocumentSerializer)
        end

        def show
          authorize LegalDocument
          render_data(LegalDocument.admin_detail(params[:slug]), serializer: LegalDocumentSerializer)
        end
      end
    end
  end
end
