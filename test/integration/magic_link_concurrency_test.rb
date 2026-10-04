require "test_helper"

class MagicLinkConcurrencyTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  test "concurrent requests can redeem a link only once" do
    user = User.create!(name: "Ana", email: "race-#{SecureRandom.hex(6)}@example.com", confirmed_at: Time.current)
    token = UserToken.issue_for(user)
    ready = Queue.new
    start = Queue.new
    responses = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          client = ActionDispatch::Integration::Session.new(Rails.application)
          ready << true
          start.pop
          client.post "/api/v1/auth/magic-links/#{token}/session", as: :json
          [ client.response.status, client.response.parsed_body ]
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = responses.map(&:value)
    assert_equal [ 201, 422 ], results.map(&:first).sort
    assert_equal "magic_link_invalid", results.find { |status, _| status == 422 }.last.dig("error", "code")
    assert_equal 1, user.sessions.count
  ensure
    user&.destroy!
  end
end
