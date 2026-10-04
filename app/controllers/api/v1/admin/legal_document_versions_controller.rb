module Api
  module V1
    module Admin
      class LegalDocumentVersionsController < BaseController
        def create
          authorize LegalDocumentVersion
          render_data(LegalDocument.create_version!(params[:legal_document_slug], version_attributes, current_scope, request), serializer: LegalDocumentVersionSerializer, status: :created)
        end

        private

        def version_attributes
          cast_legal_attributes
        end
      end
    end
  end
end
