require "test_helper"
require_relative "../support/tenancy_requests"

class InvitationJobsTest < ActionDispatch::IntegrationTest
  include TenancyRequests

  test "recurring cleanup removes expired invitations across tenants and preserves live invitations" do
    expired, expired_token = invite("expired@example.com")
    live, live_token = invite("live@example.com")
    other_token = sign_in(create_user)
    other_scope = Session.scope_for(Session.find_by_token(other_token))
    other_expired, = invite("other-expired@example.com", headers: bearer(other_token))
    other_live, = invite("other-live@example.com", headers: bearer(other_token))
    Invitation.for(@scope).find(expired).update!(expires_at: Time.current)
    Invitation.for(other_scope).find(other_expired).update!(expires_at: 1.day.ago, accepted_at: 2.days.ago)
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production").fetch("purge_expired_invitations")
    assert_equal "default", recurring.fetch("queue")
    assert recurring.fetch("schedule").present?
    recurring.fetch("class").constantize.perform_now
    refute Invitation.for(@scope).exists?(expired)
    refute Invitation.for(other_scope).exists?(other_expired)
    assert Invitation.for(@scope).exists?(live)
    assert Invitation.for(other_scope).exists?(other_live)
    get "/api/v1/invitations/#{expired_token}"
    assert_error :unprocessable_entity, "invitation_invalid"
    get "/api/v1/invitations/#{live_token}"
    assert_response :ok
  end

  test "queued invitation is retried in one hour when mail becomes unavailable" do
    post "/api/v1/settings/invitations", params: { email: "retry@example.com" }, headers: bearer(@owner_token), as: :json
    assert_response :created
    job = enqueued_jobs.find { |entry| entry[:job] == InvitationDeliveryJob }
    assert job
    previous = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :smtp
    ENV.delete("SMTP_ADDRESS")
    assert_enqueued_with job: InvitationDeliveryJob, at: ->(time) { time.between?(59.minutes.from_now, 61.minutes.from_now) } do
      InvitationDeliveryJob.perform_now(*job.fetch(:args))
    end
    assert_empty ActionMailer::Base.deliveries
    ActionMailer::Base.delivery_method = :test
    InvitationDeliveryJob.perform_now(*job.fetch(:args))
    assert_equal 1, ActionMailer::Base.deliveries.length
  ensure
    ActionMailer::Base.delivery_method = previous
  end

  test "delivery skips revoked or expired invitations and honours staging recipients" do
    previous_allowed = ENV["MAIL_ALLOWED_RECIPIENTS"]
    ENV["MAIL_ALLOWED_RECIPIENTS"] = "allowed@example.com,*@allowed.test"
    [ "outside@example.com", "allowed@example.com", "person@allowed.test" ].each do |email|
      post "/api/v1/settings/invitations", params: { email: email }, headers: bearer(@owner_token), as: :json
      assert_response :created
    end
    perform_enqueued_jobs
    assert_equal [ "allowed@example.com", "person@allowed.test" ], ActionMailer::Base.deliveries.flat_map(&:to).sort
    post "/api/v1/settings/invitations", params: { email: "revoked@allowed.test" }, headers: bearer(@owner_token), as: :json
    delete "/api/v1/settings/invitations/#{data.fetch('id')}", headers: bearer(@owner_token)
    assert_response :no_content
    post "/api/v1/settings/invitations", params: { email: "expired@allowed.test" }, headers: bearer(@owner_token), as: :json
    Invitation.for(@scope).find(data.fetch("id")).update!(expires_at: Time.current)
    perform_enqueued_jobs
    assert_equal 2, ActionMailer::Base.deliveries.length
  ensure
    ENV["MAIL_ALLOWED_RECIPIENTS"] = previous_allowed
  end
end
