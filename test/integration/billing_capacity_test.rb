require "test_helper"
require_relative "../support/billing_requests"

class BillingCapacityTest < ActionDispatch::IntegrationTest
  include BillingRequests

  test "recurring inbox cleanup preserves pending and recent events" do
    old = BillingEvent.create!(stripe_event_id: "evt_old", type: "test", livemode: false, processed_at: 31.days.ago)
    pending = BillingEvent.create!(stripe_event_id: "evt_pending", type: "test", livemode: false, created_at: 31.days.ago)
    recent = BillingEvent.create!(stripe_event_id: "evt_recent", type: "test", livemode: false, processed_at: Time.current)
    BillingEventCleanupJob.perform_now
    refute BillingEvent.exists?(old.id)
    assert BillingEvent.exists?(pending.id)
    assert BillingEvent.exists?(recent.id)
  end

  test "invitations refuse full free organizations and acceptance rechecks capacity" do
    guest = create_user
    _, invitation_token = invite(guest.email)
    2.times { seat(create_user) }
    assert_no_difference [ "Invitation.count", "AuditEvent.count" ] do
      post "/api/v1/settings/invitations", params: { email: "over-cap@example.com", role: "member", access: "full" },
        headers: bearer(@owner_token), as: :json
    end
    assert_error :unprocessable_entity, "limit_reached"
    guest_token = sign_in(guest)
    assert_no_difference [ "Membership.count", "AuditEvent.count" ] do
      post "/api/v1/invitations/#{invitation_token}/acceptance", headers: bearer(guest_token), as: :json
    end
    assert_error :unprocessable_entity, "limit_reached"
    assert_nil Invitation.for(@scope).find_by!(email: guest.email).accepted_at
    stored_subscription
    post "/api/v1/invitations/#{invitation_token}/acceptance", headers: bearer(guest_token), as: :json
    assert_response :created
    assert_equal 4, Membership.for(@scope).count
    post "/api/v1/settings/invitations", params: { email: "paid-cap@example.com", role: "member", access: "full" },
      headers: bearer(@owner_token), as: :json
    assert_response :created
  end

  test "capacity guard counts and writes under the organization lock and refuses the next seat" do
    2.times do
      candidate = create_user
      Billing.with_capacity(@scope, :members, count: -> { Membership.for(@scope).count }) do
        Membership.for(@scope).create!(user: candidate, role: "member", access: "full")
      end
    end
    candidate = create_user
    assert_no_difference "Membership.for(@scope).count" do
      error = assert_raises(ApiError) do
        Billing.with_capacity(@scope, :members, count: -> { Membership.for(@scope).count }) do
          Membership.for(@scope).create!(user: candidate, role: "member", access: "full")
        end
      end
      assert_equal "limit_reached", error.code
    end
    get "/api/v1/settings/members", headers: bearer(@owner_token)
    assert_response :ok
    assert_equal 3, data.length
    stored_subscription
    Billing.with_capacity(@scope, :members, count: -> { Membership.for(@scope).count }) do
      Membership.for(@scope).create!(user: candidate, role: "member", access: "full")
    end
    assert_equal 4, Membership.for(@scope).count
  end

  test "billing disabled permits capacity beyond the free plan and failed writes roll back" do
    Flags.with(:billing, false) do
      assert_equal "allowed", Billing.with_capacity(@scope, :members, count: -> { 10_000 }) { "allowed" }
    end
    assert_no_difference "Membership.for(@scope).count" do
      assert_raises(RuntimeError) do
        Billing.with_capacity(@scope, :members, count: -> { Membership.for(@scope).count }) do
          Membership.for(@scope).create!(user: create_user, role: "member", access: "full")
          raise "Write failed"
        end
      end
    end
    assert_raises(KeyError) { Billing.limit(@scope, :unknown) }
  end
end
