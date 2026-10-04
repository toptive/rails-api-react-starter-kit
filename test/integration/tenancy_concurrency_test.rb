require "test_helper"
require_relative "../support/auth_requests"

class TenancyConcurrencyTest < ActionDispatch::IntegrationTest
  include AuthRequests
  self.use_transactional_tests = false

  setup do
    @users = []
    @organization_ids = []
  end

  teardown do
    @organization_ids |= @users.flat_map { |user| Organization.for_user(user).map(&:id) }
    @users.each(&:destroy!)
    Organization.where(id: @organization_ids).destroy_all
  end

  test "two owners cannot leave concurrently and remove the final owner" do
    scope, owners = two_owners
    results = race(owners.map { |id, token| [ :delete, "/api/v1/settings/members/#{id}", token, nil ] })
    assert_equal [ 204, 409 ], results.map(&:first).sort
    assert_equal "last_owner", results.find { |status, _| status == 409 }.last.dig("error", "code")
    assert_equal 1, Membership.for(scope).where(role: "owner").count
  end

  test "two owners cannot demote themselves concurrently and remove the final owner" do
    scope, owners = two_owners
    results = race(owners.map { |id, token| [ :put, "/api/v1/settings/members/#{id}", token, { role: "admin" } ] })
    assert_equal [ 200, 422 ], results.map(&:first).sort
    error = results.find { |status, _| status == 422 }.last
    assert_equal "validation.last_owner", error.dig("error", "details", "role", 0, "key")
    assert_equal 1, Membership.for(scope).where(role: "owner").count
  end

  test "a manager demoted while waiting on the organization lock loses write authority" do
    owner = tracked_user
    owner_token = sign_in(owner)
    scope = Session.scope_for(Session.find_by_token(owner_token))
    @organization_ids << scope.organization.id
    actor = tracked_user
    actor_membership = Membership.for(scope).create!(user: actor, role: "admin", access: "full")
    actor.update!(last_organization_id: scope.organization.id)
    actor_token = sign_in(actor)
    target = Membership.for(scope).create!(user: tracked_user, role: "member", access: "full")
    ready = Queue.new
    worker = nil
    Organization.transaction do
      scope.organization.lock!
      worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          ready << connection.raw_connection.backend_pid
          client = ActionDispatch::Integration::Session.new(Rails.application)
          client.put "/api/v1/settings/members/#{target.id}", params: { role: "admin" }, headers: bearer(actor_token), as: :json
          [ client.response.status, client.response.parsed_body ]
        end
      end
      pid = ready.pop
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
      ActiveRecord::Base.uncached do
        until ActiveRecord::Base.connection.select_value("SELECT EXISTS(SELECT 1 FROM pg_locks WHERE pid = #{Integer(pid)} AND NOT granted)")
          assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC), :<, deadline,
            "request did not reach the organization lock (worker: #{worker.status.inspect})"
          sleep 0.01
        end
      end
      actor_membership.update!(role: "member")
    end
    status, payload = worker.value
    assert_equal 403, status
    assert_equal "forbidden", payload.dig("error", "code")
    assert_equal "member", Membership.for(scope).find(target.id).role
    refute AuditEvent.exists?(action: "membership.updated", subject_id: target.id)
  ensure
    worker&.join
  end

  test "concurrent acceptance consumes an invitation once and creates one membership" do
    owner = tracked_user
    owner_token = sign_in(owner)
    scope = Session.scope_for(Session.find_by_token(owner_token))
    @organization_ids << scope.organization.id
    guest = tracked_user
    guest_token = sign_in(guest)
    perform_enqueued_jobs do
      post "/api/v1/settings/invitations", params: { email: guest.email }, headers: bearer(owner_token), as: :json
    end
    assert_response :created
    invitation_id = data.fetch("id")
    raw = ActionMailer::Base.deliveries.last.text_part.body.decoded[%r{/invitations/([A-Za-z0-9_-]{43})}, 1]
    assert raw
    results = race(Array.new(2) { [ :post, "/api/v1/invitations/#{raw}/acceptance", guest_token, {} ] })
    assert_equal [ 201, 422 ], results.map(&:first).sort
    assert_equal "invitation_invalid", results.find { |status, _| status == 422 }.last.dig("error", "code")
    assert_equal 1, Membership.for(scope).where(user_id: guest.id).count
    assert_equal 1, AuditEvent.where(action: "invitation.accepted", subject_id: invitation_id).count
  end

  test "concurrent first users in single mode create one shared owner" do
    Rails.application.config.x.tenancy = "single"
    users = Array.new(2) { tracked_user(password: "strong-password-123") }
    shared = Organization.ensure_default!
    @organization_ids << shared.id
    results = race(users.map { |user| [ :post, "/api/v1/auth/sessions", nil, { email: user.email, password: "strong-password-123" } ] })
    assert_equal [ 201, 201 ], results.map(&:first)
    scope = Session::Scope.new(organization: shared)
    assert_equal 1, Membership.for(scope).where(role: "owner").count
    assert_equal 1, Membership.for(scope).where(role: "member").count
    results.each do |_, payload|
      session = Session.find_by_token(payload.dig("data", "token"))
      assert_equal shared.id, session.organization_id
    end
  end

  test "organization audits and analytics respect the enclosing transaction" do
    user = tracked_user
    token = sign_in(user)
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("organization_created") { |*arguments| events << arguments.last }
    before_organizations = Organization.count
    before_audits = AuditEvent.where(action: "organization.created").count
    original_org = Session.find_by_token(token).organization_id
    Organization.transaction do
      post "/api/v1/organizations", params: { name: "Rolled back" }, headers: bearer(token), as: :json
      assert_response :created
      assert_empty events
      raise ActiveRecord::Rollback
    end
    assert_equal before_organizations, Organization.count
    assert_equal before_audits, AuditEvent.where(action: "organization.created").count
    assert_equal original_org, Session.find_by_token(token).organization_id
    assert_empty events
    post "/api/v1/organizations", params: { name: "Committed" }, headers: bearer(token), as: :json
    assert_response :created
    assert_equal 1, events.length
    assert_equal data.fetch("id"), events.first.fetch(:organization_id)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  test "onboarding analytics is emitted after commit with the skipped answer" do
    owner = tracked_user
    token = sign_in(owner)
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("onboarding_completed") { |*arguments| events << arguments.last }
    Organization.transaction do
      put "/api/v1/onboarding", params: {}, headers: bearer(token), as: :json
      assert_response :ok
      assert_empty events
      raise ActiveRecord::Rollback
    end
    assert_empty events
    refute AuditEvent.exists?(action: "organization.onboarded", actor_id: owner.id)
    put "/api/v1/onboarding", params: { name: "   " }, headers: bearer(token), as: :json
    assert_response :ok
    assert_equal 1, events.length
    assert_equal true, events.first.fetch(:skipped)
    assert_equal owner.id, events.first.fetch(:user_id)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  private

  def tracked_user(**attributes)
    create_user(**attributes).tap { |user| @users << user }
  end

  def two_owners
    first = tracked_user
    token = sign_in(first)
    scope = Session.scope_for(Session.find_by_token(token))
    @organization_ids << scope.organization.id
    second = tracked_user
    membership = Membership.for(scope).create!(user: second, role: "owner", access: "full")
    second.update!(last_organization_id: scope.organization.id)
    second_token = sign_in(second)
    [ scope, [ [ scope.membership.id, token ], [ membership.id, second_token ] ] ]
  end

  def race(requests)
    ready = Queue.new
    start = Queue.new
    threads = requests.map do |method, path, token, attributes|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          client = ActionDispatch::Integration::Session.new(Rails.application)
          ready << true
          start.pop
          client.public_send(method, path, params: attributes, headers: token ? bearer(token) : {}, as: :json)
          [ client.response.status, client.response.body.present? ? client.response.parsed_body : nil ]
        end
      end
    end
    requests.length.times { ready.pop }
    requests.length.times { start << true }
    threads.map(&:value)
  ensure
    threads&.each { |thread| thread.join if thread.alive? }
  end
end
