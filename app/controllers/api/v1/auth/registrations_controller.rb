module Api
  module V1
    module Auth
      class RegistrationsController < BaseController
        skip_before_action :authenticate!
        rate_limit to: 10, within: 1.minute, store: RATE_LIMIT_STORE, with: :render_rate_limited

        def create
          skip_authorization
          attributes = params.permit(:name, :email, :locale, :terms_accepted, :turnstile_token).to_h.symbolize_keys
          attributes[:locale] ||= I18n.locale.to_s
          render_data(User.register(attributes, request), serializer: MagicLinkRequestSerializer, status: :accepted)
        end
      end
    end
  end
end
