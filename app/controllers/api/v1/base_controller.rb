module Api
  module V1
    class BaseController < ApplicationController
      RATE_LIMIT_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

      before_action :authenticate!

      private

      def current_user = current_session&.user
      def current_scope = @current_scope ||= Session.scope_for(current_session)
      def current_session = @current_session ||= Session.find_by_token(bearer_token)
      def locale_user = current_user
      def pundit_user = current_scope

      def authenticate!
        @current_session = Session.authenticate(bearer_token)
      end

      def require_sudo!
        raise ApiError.forbidden(:sudo_required) unless current_session&.sudo?
      end

      def require_superadmin!
        raise ApiError.not_found unless current_session&.superadmin?
      end

      def bearer_token
        request.authorization.to_s[/\ABearer ([^\s,]+)\z/i, 1]
      end
    end
  end
end
