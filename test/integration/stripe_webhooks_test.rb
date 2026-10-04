require "test_helper"
require_relative "../support/billing_requests"

class StripeWebhooksTest < ActionDispatch::IntegrationTest
  include BillingRequests

  test "a good signed webhook is stored once and repeated delivery does not enqueue twice" do
    assert_difference "BillingEvent.count", 1 do
      assert_enqueued_jobs 1, only: ProcessStripeEventJob do
        2.times do
          deliver_webhook
          assert_response :ok
          assert_equal({ "received" => true }, data)
        end
      end
    end
    event = BillingEvent.find_by!(stripe_event_id: "evt_paid")
    assert_equal @organization.id, event.organization_id
    assert_equal "sub_paid", event.stripe_subscription_id
    assert_nil event.processed_at
    refute event.respond_to?(:payload)
  end

  test "invalid tampered stale and future signatures are refused without writes" do
    [ { signature: "bad" }, { secret: "whsec_wrong" }, { timestamp: 301.seconds.ago.to_i },
      { timestamp: 301.seconds.from_now.to_i } ].each do |options|
      assert_no_difference "BillingEvent.count" do
        assert_no_enqueued_jobs(only: ProcessStripeEventJob) { deliver_webhook(**options) }
      end
      assert_error :bad_request, "invalid_signature"
    end
    raw = '{ "id": "evt_raw", "type": "unhandled", "livemode": false }'
    signature = "t=#{Time.current.to_i},v1=#{OpenSSL::HMAC.hexdigest('SHA256', 'whsec_stub', "#{Time.current.to_i}.#{raw}")}"
    deliver_webhook(raw: JSON.generate(JSON.parse(raw)), signature: signature)
    assert_error :bad_request, "invalid_signature"
    deliver_webhook(raw: "not-json")
    assert_error :bad_request, "invalid_signature"
  end

  test "raw JSON whitespace is preserved and a rotating secret signature is accepted" do
    raw = "{\n  \"id\": \"evt_spaces\", \"type\": \"unhandled\", \"livemode\": false\n}"
    timestamp = Time.current.to_i
    good = OpenSSL::HMAC.hexdigest("SHA256", "whsec_stub", "#{timestamp}.#{raw}")
    deliver_webhook(raw: raw, signature: "t=#{timestamp},v1=#{'0' * 64},v1=#{good}")
    assert_response :ok
    assert_no_difference("BillingEvent.count") { deliver_webhook(raw: raw) }
    assert_response :ok
  end

  test "wrong mode refuses while an unknown event is acknowledged without storage" do
    deliver_webhook(webhook_event(livemode: true))
    assert_error :bad_request, "invalid_signature"
    assert_no_difference "BillingEvent.count" do
      assert_no_enqueued_jobs(only: ProcessStripeEventJob) { deliver_webhook(webhook_event(type: "charge.succeeded")) }
    end
    assert_response :ok
  end

  test "missing secret is 404 and billing disabled still receives renewals and cancellations" do
    ENV.delete("STRIPE_TEST_WEBHOOK_SECRET")
    deliver_webhook
    assert_error :not_found, "not_found"
    ENV["STRIPE_TEST_WEBHOOK_SECRET"] = "whsec_stub"
    Flags.with(:billing, false) { deliver_webhook }
    assert_response :ok
    assert BillingEvent.exists?(stripe_event_id: "evt_paid")
  end

  test "every handled event extracts subscription ids including modern invoices" do
    Billing::Webhook::HANDLED.each_with_index do |type, index|
      object = if type.start_with?("customer.subscription.")
        { id: "sub_paid", metadata: { organization_id: @organization.id } }
      elsif type.start_with?("invoice.")
        { parent: { subscription_details: { subscription: "sub_paid", metadata: { organization_id: @organization.id } } } }
      else
        { subscription: "sub_paid", client_reference_id: @organization.id }
      end
      deliver_webhook(webhook_event(id: "evt_#{index}", type: type, object: object))
      assert_response :ok
      event = BillingEvent.find_by!(stripe_event_id: "evt_#{index}")
      assert_equal "sub_paid", event.stripe_subscription_id
      assert_equal @organization.id, event.organization_id
    end
  end

  test "reconciliation fetches Stripe truth and ignores a forged plan from the webhook" do
    object = { subscription: "sub_paid", metadata: { organization_id: @organization.id }, plan: "forged", status: "canceled" }
    with_stripe(subscription: stripe_subscription(current_period_end: nil,
      items: { data: [ { current_period_end: 3.days.from_now.to_i, price: { id: "price_monthly" } } ] })) do
      perform_enqueued_jobs(only: ProcessStripeEventJob) { deliver_webhook(webhook_event(object: object)) }
    end
    subscription = Billing.current(@scope)
    assert_equal "pro", subscription.plan
    assert_equal "active", subscription.status
    assert subscription.paid?
    assert_in_delta 3.days.from_now.to_i, subscription.current_period_end.to_i, 1
    with_stripe(subscription: stripe_subscription(status: "canceled")) do
      perform_enqueued_jobs(only: ProcessStripeEventJob) { deliver_webhook(webhook_event(id: "evt_canceled", type: "customer.subscription.deleted", object: { id: "sub_paid" })) }
    end
    get "/api/v1/settings/billing", headers: bearer(@owner_token)
    assert_equal "free", data.fetch("plan")
    assert_equal false, data.dig("subscription", "paid")
  end

  test "a different unpaid subscription cannot replace a paid one and unknown prices grant no entitlement" do
    paid = stored_subscription
    with_stripe(subscription: stripe_subscription(id: "sub_old", status: "canceled")) do
      perform_enqueued_jobs(only: ProcessStripeEventJob) do
        deliver_webhook(webhook_event(id: "evt_old", object: { subscription: "sub_old" }))
      end
    end
    assert_equal "kept_paid_subscription", BillingEvent.find_by!(stripe_event_id: "evt_old").outcome
    assert_equal paid.id, Billing.current(@scope).id
    assert Billing.current(@scope).paid?
    with_stripe(subscription: stripe_subscription(items: { data: [ { price: { id: "price_unknown" } } ] }, metadata: { organization_id: @organization.id, offer_id: "pro_monthly" })) do
      perform_enqueued_jobs(only: ProcessStripeEventJob) { deliver_webhook(webhook_event(id: "evt_unknown_price")) }
    end
    assert_nil Billing.current(@scope).offer_id
    assert_equal "free", Billing.plan(@scope)
  end

  test "missing subscription unknown organization wrong mode and provider retry outcomes" do
    perform_enqueued_jobs(only: ProcessStripeEventJob) { deliver_webhook(webhook_event(id: "evt_none", object: {})) }
    assert_equal "no_subscription", BillingEvent.find_by!(stripe_event_id: "evt_none").outcome
    with_stripe(subscription: stripe_subscription(metadata: { organization_id: SecureRandom.uuid })) do
      perform_enqueued_jobs(only: ProcessStripeEventJob) { deliver_webhook(webhook_event(id: "evt_unknown")) }
    end
    assert_equal "unknown_organization", BillingEvent.find_by!(stripe_event_id: "evt_unknown").outcome
    with_stripe(subscription: stripe_subscription(livemode: true)) do
      perform_enqueued_jobs(only: ProcessStripeEventJob) { deliver_webhook(webhook_event(id: "evt_wrong")) }
    end
    assert_equal "wrong_mode", BillingEvent.find_by!(stripe_event_id: "evt_wrong").outcome
    deliver_webhook(webhook_event(id: "evt_retry"))
    assert_response :ok
    pending = BillingEvent.find_by!(stripe_event_id: "evt_retry")
    with_stripe(error: :timeout) do
      assert_enqueued_with(job: ProcessStripeEventJob) { ProcessStripeEventJob.perform_now(pending.id) }
    end
    assert_nil pending.reload.processed_at
  end

  test "changing deployment mode finishes old events without calling the other mode's provider" do
    deliver_webhook
    ENV["BILLING_MODE"] = "live"
    Net::HTTP.stub(:new, ->(*) { flunk "Old mode must not call Stripe with another mode's key" }) do
      ProcessStripeEventJob.perform_now(BillingEvent.find_by!(stripe_event_id: "evt_paid").id)
    end
    assert_equal "wrong_mode", BillingEvent.find_by!(stripe_event_id: "evt_paid").outcome
  end

  test "a failed queue insertion rolls back the webhook inbox" do
    ProcessStripeEventJob.stub(:perform_later, ->(*) { raise ActiveRecord::StatementInvalid, "Queue unavailable" }) do
      assert_no_difference "BillingEvent.count" do
        assert_raises(ActiveRecord::StatementInvalid) { deliver_webhook }
      end
    end
  end

  test "real Solid Queue shares the inbox transaction and rollback removes both rows" do
    adapter = ProcessStripeEventJob.queue_adapter
    ProcessStripeEventJob.disable_test_adapter
    ProcessStripeEventJob.queue_adapter = :solid_queue
    assert_same ActiveRecord::Base.connection_pool, SolidQueue::Record.connection_pool
    assert_no_difference [ "BillingEvent.count", "SolidQueue::Job.count" ] do
      BillingEvent.transaction do
        deliver_webhook
        assert_response :ok
        assert_equal 1, BillingEvent.where(stripe_event_id: "evt_paid").count
        job = SolidQueue::Job.find_by!(class_name: "ProcessStripeEventJob")
        assert_equal "default", job.queue_name
        assert_equal BillingEvent.find_by!(stripe_event_id: "evt_paid").id, job.arguments.fetch("arguments").first
        raise ActiveRecord::Rollback
      end
    end
  ensure
    ProcessStripeEventJob.queue_adapter = adapter
  end

  test "webhooks rate limit work at 600 requests per minute" do
    600.times do |index|
      deliver_webhook(webhook_event(id: "evt_ignored_#{index}", type: "unhandled"))
      assert_response :ok
    end
    deliver_webhook
    assert_error :too_many_requests, "rate_limited"
    assert_equal "60", response.headers["Retry-After"]
  end
end
