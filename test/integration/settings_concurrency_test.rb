require "test_helper"
require_relative "../support/settings_requests"

class SettingsConcurrencyTest < ActionDispatch::IntegrationTest
  include SettingsRequests
  self.use_transactional_tests = false

  setup do
    @users = [ @owner ]
    @organizations = [ @organization ]
  end

  teardown do
    @users.each { |user| user.destroy! if User.exists?(user.id) }
    @organizations.each { |organization| organization.destroy! if Organization.exists?(organization.id) }
  end

  test "deletion waits for the organization lock and rechecks a newly added member" do
    member = create_user
    @users << member
    ready = Queue.new
    worker = nil
    Organization.transaction do
      @organization.lock!
      worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          ready << connection.raw_connection.backend_pid
          client = ActionDispatch::Integration::Session.new(Rails.application)
          client.delete "/api/v1/settings/account", headers: bearer(@owner_token)
          [ client.response.status, client.response.parsed_body ]
        end
      end
      pid = ready.pop
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
      ActiveRecord::Base.uncached do
        until ActiveRecord::Base.connection.select_value("SELECT EXISTS(SELECT 1 FROM pg_locks WHERE pid = #{Integer(pid)} AND NOT granted)")
          assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC), :<, deadline
          sleep 0.01
        end
      end
      Membership.for(@scope).create!(user: member, role: "member", access: "full")
    end
    status, payload = worker.value
    assert_equal 409, status
    assert_equal "transfer_ownership", payload.dig("error", "code")
    assert_equal @organization.name, payload.dig("error", "details", "organization")
    assert User.exists?(@owner.id)
    assert_equal 2, Membership.for(@scope).count
    refute AuditEvent.exists?(action: "user.deleted", subject_id: @owner.id)
  ensure
    worker&.join
  end

  test "concurrent email confirmation applies only one change and invalidates every other token" do
    raw = 2.times.map do |index|
      UserToken.issue_for(@owner, context: "change_email:#{@owner.email}", sent_to: "new#{index}@example.com")
    end
    ready = Queue.new
    start = Queue.new
    workers = raw.map do |token|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          client = ActionDispatch::Integration::Session.new(Rails.application)
          ready << true
          start.pop
          client.post "/api/v1/settings/email-confirmations", params: { token: token }, headers: bearer(@owner_token), as: :json
          [ client.response.status, client.response.parsed_body ]
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    responses = workers.map(&:value)
    assert_equal [ 200, 422 ], responses.map(&:first).sort
    assert_equal "email_change_invalid", responses.find { |status, _| status == 422 }.last.dig("error", "code")
    assert_empty @owner.user_tokens.where("context LIKE ?", "change_email:%")
    assert_equal 1, AuditEvent.where(action: "user.email_changed", subject_id: @owner.id).count
  ensure
    workers&.each(&:join)
  end
end
