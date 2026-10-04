module Api
  module V1
    module Admin
      module LegalDocuments
        module Versions
          class PublicationController < BaseController
            def create
              authorize LegalDocument, :create?
              render_data(LegalDocument.publish_version!(params[:legal_document_slug], params[:version_number], current_scope, request), serializer: LegalDocumentSerializer, status: :created)
            end
          end
        end
      end
    end
  end
end
