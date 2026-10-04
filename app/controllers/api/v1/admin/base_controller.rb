module Api
  module V1
    module Admin
      class BaseController < Api::V1::BaseController
        skip_before_action :authenticate!
        before_action :require_superadmin!

        private

        def search_query = cast_string_attributes(:q)[:q]&.strip
      end
    end
  end
end
