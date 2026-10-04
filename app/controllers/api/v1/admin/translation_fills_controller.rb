module Api
  module V1
    module Admin
      class TranslationFillsController < BaseController
        def create
          authorize Translation, :create?
          render_data(Translation.fill!(cast_string_attributes(:locale), current_scope, request), serializer: TranslationFillSerializer, status: :created)
        end
      end
    end
  end
end
