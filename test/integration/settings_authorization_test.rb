require "test_helper"
require_relative "../support/settings_requests"

class SettingsAuthorizationTest < ActionDispatch::IntegrationTest
  include SettingsRequests

  ENDPOINTS = [ [ :put, "/profile" ], [ :get, "/email-preferences" ], [ :put, "/email-preferences" ],
    [ :get, "/sessions" ], [ :delete, "/sessions/missing" ], [ :put, "/email" ],
    [ :get, "/email-confirmations/missing" ], [ :post, "/email-confirmations" ], [ :put, "/password" ],
    [ :get, "/account" ], [ :delete, "/account" ] ].freeze
  SUDO_ENDPOINTS = [ [ :put, "/email" ], [ :put, "/password" ], [ :get, "/account" ], [ :delete, "/account" ] ].freeze

  ENDPOINTS.each do |method, path|
    test "#{method} #{path} requires a bearer" do
      public_send method, "/api/v1/settings#{path}", as: :json
      assert_error :unauthorized, "unauthorized"
    end

    test "#{method} #{path} refuses a revoked bearer as session expired" do
      @scope.session.update!(revoked_at: Time.current)
      public_send method, "/api/v1/settings#{path}", headers: bearer(@owner_token), as: :json
      assert_error :unauthorized, "session_expired"
    end
  end

  SUDO_ENDPOINTS.product(%w[missing expired impersonation]).each do |(method, path), state|
    test "#{method} #{path} refuses #{state} sudo before any writes" do
      case state
      when "missing"
        @scope.session.update!(sudo_until: nil)
      when "expired"
        @scope.session.update!(sudo_until: Time.current)
      when "impersonation"
        @scope.session.update!(impersonator_user: create_user(role: "superadmin"), sudo_until: nil)
      end
      assert_no_difference [ "User.count", "Session.count", "UserToken.count", "AuditEvent.count" ] do
        public_send method, "/api/v1/settings#{path}", params: method == :get ? nil : { email: "new@example.com", password: "updated-password-123", passwordConfirmation: "updated-password-123" },
          headers: bearer(@owner_token), as: :json
      end
      assert_error :forbidden, "sudo_required"
      assert_equal({}, response.parsed_body.dig("error", "details"))
    end
  end

  test "settings PUT resources do not expose PATCH routes" do
    %w[profile email-preferences email password].each do |resource|
      patch "/api/v1/settings/#{resource}", params: {}, headers: bearer(@owner_token), as: :json
      assert_error :method_not_allowed, "method_not_allowed"
    end
  end
end
