require "test_helper"
require_relative "../support/auth_requests"

class SessionCleanupTest < ActionDispatch::IntegrationTest
  include AuthRequests

  test "daily cleanup prunes old sessions and expired tokens while retaining live and recently expired rows" do
    user = create_user
    tokens = 4.times.map { sign_in(user) }
    rows = tokens.map { |token| Session.find_by_token(token) }
    rows[0].update!(expires_at: 31.days.ago)
    rows[1].update!(revoked_at: 31.days.ago)
    rows[2].update!(expires_at: 1.day.ago)
    UserToken.issue_for(user)
    UserToken.where(user: user).update_all(expires_at: Time.current)
    fresh = UserToken.issue_for(user)
    SessionCleanupJob.perform_now
    assert_equal rows.last(2).map(&:id).sort, user.sessions.pluck(:id).sort
    assert_equal 1, user.user_tokens.count
    get "/api/v1/auth/magic-links/#{fresh}"
    assert_response :ok
  end
end
