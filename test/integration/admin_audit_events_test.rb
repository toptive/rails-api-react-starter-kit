require "test_helper"
require_relative "../support/admin_requests"

class AdminAuditEventsTest < ActionDispatch::IntegrationTest
  include AdminRequests

  test "audit index searches action literally and paginates newest first with actor emails" do
    scope = Session.scope_for(Session.find_by_token(@admin_token))
    first = Audit.record("example%_literal", scope: scope, subject: @admin, metadata: { camelCase: { nestedKey: "value" } })
    second = Audit.record("example%_literal", scope: scope, subject: @admin)
    Audit.record("example-other", scope: scope)
    get "/api/v1/admin/audit-events", params: { q: "EXAMPLE%_", perPage: 1 }, headers: admin_headers
    assert_response :ok
    assert_equal [ second.id ], data.map { |event| event.fetch("id") }
    assert_equal @admin.email, data.first.fetch("actorEmail")
    assert_equal 2, response.parsed_body.dig("meta", "pagination", "total")
    get "/api/v1/admin/audit-events", params: { q: "EXAMPLE%_", perPage: 1, page: 2 }, headers: admin_headers
    assert_equal first.id, data.first.fetch("id")
    assert_equal({ "camelCase" => { "nestedKey" => "value" } }, data.first.fetch("metadata"))
    assert data.first.fetch("insertedAt").end_with?("Z")
    refute data.first.key?("ipAddress")
  end

  test "UUID search matches actor or subject and a deleted actor has no email" do
    actor = create_user
    subject = create_user
    matched_actor = Audit.record("example.actor", actor: actor, subject: subject)
    matched_subject = Audit.record("example.subject", actor: @admin, subject: actor)
    Audit.record("example.unrelated", actor: @admin)
    actor.destroy!
    get "/api/v1/admin/audit-events", params: { q: actor.id.upcase }, headers: admin_headers
    assert_response :ok
    assert_equal [ matched_subject.id, matched_actor.id ], data.map { |event| event.fetch("id") }
    assert_nil data.last.fetch("actorEmail")
    get "/api/v1/admin/audit-events", params: { q: "absent" }, headers: admin_headers
    assert_response :ok
    assert_empty data
  end
end
