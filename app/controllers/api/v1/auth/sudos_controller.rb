module Api
  module V1
    module Auth
      class SudosController < BaseController
        rate_limit to: 5, within: 1.minute, store: RATE_LIMIT_STORE, with: :render_rate_limited

        def create
          authorize current_session, :update?
          render_data(current_session.elevate!(params.permit(:password, :magic_link_token).to_h.symbolize_keys, request),
            serializer: SudoWindowSerializer)
        end
      end
    end
  end
end
