require_relative "auth_requests"

module TenancyRequests
  extend ActiveSupport::Concern
  include AuthRequests

  included do
    setup do
      @owner = create_user(name: "Owner")
      @owner_token = sign_in(@owner)
      @scope = Session.scope_for(Session.find_by_token(@owner_token))
      @organization = @scope.organization
    end
  end

  def seat(user, role: "member", access: "full", scope: @scope)
    Membership.for(scope).create!(user: user, role: role, access: access)
  end

  def signed_member(role: "member", access: "full")
    user = create_user
    membership = seat(user, role: role, access: access)
    user.update!(last_organization_id: @organization.id)
    [ user, sign_in(user), membership ]
  end

  def invite(email, role: "member", access: "full", headers: bearer(@owner_token))
    perform_enqueued_jobs do
      post "/api/v1/settings/invitations", params: { email: email, role: role, access: access }, headers: headers, as: :json
    end
    assert_response :created
    id = data.fetch("id")
    token = ActionMailer::Base.deliveries.last.text_part.body.decoded[%r{/invitations/([A-Za-z0-9_-]{43})}, 1]
    assert token
    [ id, token ]
  end

  def assert_field_error(field, key, bindings: nil)
    assert_error :unprocessable_entity, "validation_failed"
    errors = response.parsed_body.dig("error", "details", field)
    error = errors.find { |item| item["key"] == key }
    assert error, "Expected #{key} on #{field}, got #{errors.inspect}"
    assert_equal I18n.t(key, **(bindings || {}).symbolize_keys), error.fetch("message")
    assert_equal bindings, error["bindings"] if bindings
  end
end
