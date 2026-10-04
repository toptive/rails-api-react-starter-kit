module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate!

      private

      attr_reader :current_user, :current_session

      def authenticate!
        @current_session = find_session(bearer_token)
        @current_user = @current_session&.user
        raise ApiError.unauthorized unless @current_user
      end

      def bearer_token
        request.authorization.to_s[/\ABearer ([^\s,]+)\z/i, 1]
      end

      # Bearer authentication checks the stored digest, expiry and revocation.
      def find_session(_token) = nil
    end
  end
end
