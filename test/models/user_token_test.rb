require "test_helper"

class UserTokenTest < ActiveSupport::TestCase
  test "emailed tokens store hashes and use context specific expiry" do
    user = User.create!(name: "Ana", email: "ana@example.com")
    travel_to Time.current.change(usec: 0)
    { "magic_link" => 15.minutes, "confirm" => 15.minutes,
      "reset_password" => 15.minutes, "change_email:ana@example.com" => 7.days }.each do |context, lifetime|
      raw = UserToken.issue_for(user, context: context)
      row = UserToken.find_by!(token_hash: Digest::SHA256.digest(raw), context: context)
      refute_equal raw, row.token_hash
      assert_equal Time.current + lifetime, row.expires_at
    end
    row = UserToken.find_by!(context: "magic_link")
    row.update!(expires_at: Time.current)
    raw = UserToken.issue_for(user)
    travel 15.minutes
    assert_raises(ApiError) { UserToken.peek(raw) }
  end
end
