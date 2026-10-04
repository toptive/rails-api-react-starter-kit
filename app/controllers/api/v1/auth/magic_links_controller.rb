module Api
  module V1
    module Auth
      class MagicLinksController < BaseController
        skip_before_action :authenticate!
        rate_limit to: 5, within: 1.minute, store: RATE_LIMIT_STORE, only: :create, with: :render_rate_limited

        def create
          skip_authorization
          render_data(User.request_magic_link(params.permit(:email, :turnstile_token).to_h.symbolize_keys, request),
            serializer: MagicLinkRequestSerializer, status: :accepted)
        end

        def show
          skip_authorization
          render_data(UserToken.peek(params[:token]), serializer: MagicLinkSerializer)
        end
      end
    end
  end
end
