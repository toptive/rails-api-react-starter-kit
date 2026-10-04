module Api
  module V1
    module Admin
      class TranslationFillsController < BaseController
        def create
          authorize Translation, :create?
          result = TranslationFill.start!(cast_string_attributes(:locale), current_scope, request)
          render_data(result, serializer: TranslationFillSerializer, status: result.fetch(:status))
        end
      end
    end
  end
end
