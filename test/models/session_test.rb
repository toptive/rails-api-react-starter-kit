require "test_helper"

class SessionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Ana", email: "ana@example.com")
    @request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/", "HTTP_USER_AGENT" => "x" * 300))
  end

  test "bearer tokens are hashed and expire or revoke without allowing arbitrary tokens" do
    issued = Session.create_for(@user, @request)
    session, token = issued.values_at(:session, :token)
    assert_equal 43, token.length
    assert_equal Digest::SHA256.digest(token), session.token_hash
    refute_equal token, session.token_hash
    assert_equal 255, session.user_agent.length
    assert_equal @user, Session.find_by_token(token).user
    assert_nil Session.find_by_token("x")
    session.update!(expires_at: Time.current)
    assert_nil Session.find_by_token(token)
    session.update!(expires_at: 1.day.from_now, revoked_at: Time.current)
    assert_nil Session.find_by_token(token)
  end

  test "sliding expiry and last used writes follow their time thresholds" do
    travel_to Time.current.change(usec: 0)
    issued = Session.create_for(@user, @request)
    session, token = issued.values_at(:session, :token)
    expires = session.expires_at
    travel 30.seconds
    Session.find_by_token(token)
    assert_equal session.last_used_at, session.reload.last_used_at
    assert_equal expires, session.expires_at
    travel 8.days
    Session.find_by_token(token)
    assert_equal 14.days.from_now, session.reload.expires_at
    assert_equal Time.current, session.last_used_at
    assert_equal Time.current, session.renewed_at
    session.update!(expires_at: 6.days.from_now)
    Session.find_by_token(token)
    assert_equal 6.days.from_now, session.reload.expires_at
  end

  test "impersonation expiry never slides and sudo cannot be established" do
    issued = Session.create_for(@user, @request)
    session, token = issued.values_at(:session, :token)
    session.update!(impersonator_user: @user, sudo_until: nil, expires_at: 8.hours.from_now)
    expires = session.expires_at
    Session.find_by_token(token)
    assert_equal expires, session.reload.expires_at
    assert_raises(ApiError) { session.touch_sudo! }
    assert_nil session.reload.sudo_until
  end
end
