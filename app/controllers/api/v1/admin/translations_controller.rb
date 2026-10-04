module Api
  module V1
    module Admin
      class TranslationsController < BaseController
        def index
          authorize Translation
          render_collection(Translation.entries(query: search_query, missing: cast_string_attributes(:missing)[:missing]), serializer: TranslationEntrySerializer)
        end

        def update
          authorize Translation
          render_data(Translation.edit!(params[:key], cast_string_attributes(:locale, :value), current_scope, request), serializer: TranslationEntrySerializer)
        end
      end
    end
  end
end
