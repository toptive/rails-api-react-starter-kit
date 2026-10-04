require "test_helper"
require_relative "../support/auth_requests"

class AuditIntegrityTest < ActionDispatch::IntegrationTest
  include AuthRequests

  test "registration audit is append only even through direct SQL" do
    post "/api/v1/auth/registrations", params: { name: "Ana", email: "ana@example.com", termsAccepted: true }, as: :json
    assert_response :accepted
    event = AuditEvent.find_by!(action: "user.registered", actor_id: User.find_by!(email: "ana@example.com").id)
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(action: "changed") }
    assert_raises(ActiveRecord::StatementInvalid) do
      AuditEvent.transaction(requires_new: true) { AuditEvent.where(id: event.id).update_all(action: "changed") }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      AuditEvent.transaction(requires_new: true) { AuditEvent.where(id: event.id).delete_all }
    end
    assert_equal "user.registered", event.reload.action
  end
end
