require "test_helper"
require_relative "../support/auth_requests"

class AdminAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthRequests

  ROUTES = [
    [ :get, "/dashboard" ], [ :get, "/users" ], [ :get, "/users/%{user}" ],
    [ :put, "/users/%{user}" ], [ :post, "/users/%{user}/impersonation" ],
    [ :get, "/organizations" ], [ :get, "/organizations/%{organization}" ],
    [ :get, "/translations" ], [ :put, "/translations/app.name" ],
    [ :post, "/translation-fills" ], [ :get, "/legal-documents" ],
    [ :get, "/legal-documents/terms" ], [ :post, "/legal-documents/terms/versions" ],
    [ :post, "/legal-documents/terms/versions/1/publication" ],
    [ :get, "/audit-events" ], [ :post, "/jobs-access" ]
  ].freeze

  ROUTES.each do |method, path|
    %w[anonymous user impersonating].each do |identity|
      test "#{method} #{path} is hidden from #{identity}" do
        target = create_user
        request_headers = case identity
        when "anonymous" then {}
        when "user" then bearer(sign_in(target))
        else
          admin = create_user(role: "superadmin")
          parent_token = sign_in(admin)
          post "/api/v1/admin/users/#{target.id}/impersonation", params: { reason: "Support investigation" }, headers: bearer(parent_token), as: :json
          assert_response :created
          bearer(data.fetch("token"))
        end
        organization = Organization.create_owned!(target, name: "Other organization")
        assert_no_difference [ "AuditEvent.count", "Translation.count", "LegalDocument.count", "JobsTicket.count", "Impersonation.count" ] do
          public_send(method, "/api/v1/admin#{format(path, user: target.id, organization: organization.id)}", headers: request_headers, as: :json)
        end
        assert_error :not_found, "not_found"
        assert_nil response.headers["Set-Cookie"]
      end
    end
  end

  test "unknown expired revoked and demoted admin bearers get 404" do
    admin = create_user(role: "superadmin")
    token = sign_in(admin)
    session = Session.find_by_token(token)
    session.update!(revoked_at: Time.current)
    [ token, "unknown" ].each do |bearer_token|
      get "/api/v1/admin/dashboard", headers: bearer(bearer_token)
      assert_error :not_found, "not_found"
    end
    session.update!(revoked_at: nil, expires_at: 1.second.ago)
    get "/api/v1/admin/dashboard", headers: bearer(token)
    assert_error :not_found, "not_found"
    session.update!(expires_at: 1.day.from_now)
    admin.update!(role: "user")
    get "/api/v1/admin/dashboard", headers: bearer(token)
    assert_error :not_found, "not_found"
  end
end
