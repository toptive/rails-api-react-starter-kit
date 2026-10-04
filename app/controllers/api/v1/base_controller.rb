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

      # Task 02 replaces this deny-by-default seam with Session.find_live(token).
      # Never accept a token until its digest and expiry can be checked in the DB.
      def find_session(_token) = nil
    end
  end
end
