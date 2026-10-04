require_relative "tenancy_requests"

module BillingRequests
  extend ActiveSupport::Concern
  include TenancyRequests

  included do
    setup do
      @billing_env = ENV.to_h.select { |key, _| key.start_with?("BILLING_", "STRIPE_", "PUBLIC_URL") }
      ENV["BILLING_MODE"] = "test"
      ENV["BILLING_ENABLED"] = "true"
      ENV["STRIPE_TEST_SECRET_KEY"] = "sk_test_stub"
      ENV["STRIPE_TEST_WEBHOOK_SECRET"] = "whsec_stub"
      ENV["STRIPE_TEST_PRICE_PRO_MONTHLY"] = "price_monthly"
      ENV["STRIPE_TEST_PRICE_PRO_YEARLY"] = "price_yearly"
      ENV["BILLING_TEST_OPERATOR_USER_IDS"] = @owner.id
      ENV["PUBLIC_URL"] = "https://public.example"
      @stripe_requests = []
    end

    teardown do
      ENV.keys.grep(/\A(?:BILLING_|STRIPE_|PUBLIC_URL)/).each { |key| ENV.delete(key) }
      @billing_env.each { |key, value| ENV[key] = value }
    end
  end

  def billing_attributes = { offerId: "pro_monthly", offerRevision: Billing.revision, accepted: true }

  def stripe_price
    { id: "price_monthly", active: true, livemode: false, unit_amount: 1900, currency: "usd",
      recurring: { interval: "month", interval_count: 1 } }
  end

  def stripe_subscription(scope: @scope, **attributes)
    { id: "sub_paid", customer: "cus_paid", livemode: false, status: "active",
      cancel_at_period_end: false, current_period_end: 30.days.from_now.to_i,
      metadata: { organization_id: scope.organization.id },
      items: { data: [ { price: { id: "price_monthly" } } ] } }.merge(attributes)
  end

  def stored_subscription(scope: @scope, **attributes)
    BillingSubscription.for(scope).create!({ stripe_customer_id: "cus_paid", stripe_subscription_id: "sub_paid",
      plan: "pro", status: "active", offer_id: "pro_monthly", livemode: false, current_period_end: 30.days.from_now }.merge(attributes))
  end

  def with_stripe(price: stripe_price, subscription: stripe_subscription, checkout_url: "https://checkout.stripe.com/c/pay",
    portal_url: "https://billing.stripe.com/p/session", error: nil, preview: { amount_due: 12345, currency: "usd" })
    http = Net::HTTP.new("api.stripe.com", 443)
    handler = ->(method, path, payload, headers) do
      assert_equal "Bearer #{ENV.fetch("STRIPE_#{Billing.mode.upcase}_SECRET_KEY")}", headers.fetch("Authorization")
      assert_equal Billing::Gateway::API_VERSION, headers.fetch("Stripe-Version")
      assert_equal 0, http.max_retries
      form = payload && URI.decode_www_form(payload).to_h
      @stripe_requests << { method: method, path: path, form: form, headers: headers }
      raise SocketError if error == :socket
      raise Net::ReadTimeout if error == :timeout

      value = case path
      when "/v1/prices/price_monthly", "/v1/prices/price_yearly" then price
      when %r{\A/v1/subscriptions/sub_} then subscription
      when "/v1/checkout/sessions" then { url: checkout_url }
      when "/v1/billing_portal/sessions" then { url: portal_url }
      when "/v1/invoices/create_preview" then preview
      else flunk "Unexpected Stripe request: #{path}"
      end
      response = error == :http ? Net::HTTPBadRequest.new("1.1", "400", "Bad") : Net::HTTPOK.new("1.1", "200", "OK")
      response.define_singleton_method(:body) { error == :malformed ? "not-json" : JSON.generate(value) }
      response
    end
    Net::HTTP.stub(:new, http) do
      http.stub(:get, ->(path, headers) { handler.call(:get, path, nil, headers) }) do
        http.stub(:post, ->(path, payload, headers) { handler.call(:post, path, payload, headers) }) { yield }
      end
    end
  end

  def webhook_event(id: "evt_paid", type: "checkout.session.completed", livemode: false, object: nil)
    object ||= { subscription: "sub_paid", metadata: { organization_id: @organization.id } }
    { id: id, type: type, livemode: livemode, data: { object: object } }
  end

  def deliver_webhook(event = webhook_event, timestamp: Time.current.to_i, secret: "whsec_stub", raw: nil, signature: nil)
    raw ||= JSON.generate(event)
    signature ||= "t=#{timestamp},v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{raw}")}"
    post "/webhooks/stripe/events", params: raw, headers: { "Content-Type" => "application/json", "Stripe-Signature" => signature }
  end
end
