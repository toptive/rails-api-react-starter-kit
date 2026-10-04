require "test_helper"
require_relative "../support/billing_requests"

class BillingCapacityTest < ActionDispatch::IntegrationTest
  include BillingRequests

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
