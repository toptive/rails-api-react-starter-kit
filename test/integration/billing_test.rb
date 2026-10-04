require "test_helper"
require_relative "../support/billing_requests"

class BillingTest < ActionDispatch::IntegrationTest
  include BillingRequests

  test "billing off hides overview and checkout but portal still reports no subscription" do
    Flags.with(:billing, false) do
      get "/api/v1/settings/billing", headers: bearer(@owner_token)
      assert_error :not_found, "not_found"
      post "/api/v1/settings/billing/checkout-session", params: billing_attributes, headers: bearer(@owner_token), as: :json
      assert_error :not_found, "not_found"
      post "/api/v1/settings/billing/portal-session", headers: bearer(@owner_token), as: :json
      assert_error :conflict, "no_subscription"
    end
  end

  test "overview is the exact contract and reports closed sales to non operators" do
    get "/api/v1/settings/billing", headers: bearer(@owner_token)
    assert_response :ok
    assert_equal %w[canManage offerRevision offers plan sales subscription], data.keys.sort
    assert_equal "free", data.fetch("plan")
    assert_equal "test", data.fetch("sales")
    assert_nil data.fetch("subscription")
    assert data.fetch("canManage")
    assert_equal [ 1900, 19000 ], data.fetch("offers").map { |offer| offer.fetch("amountCents") }
    ENV["BILLING_TEST_OPERATOR_USER_IDS"] = ""
    get "/api/v1/settings/billing", headers: bearer(@owner_token)
    assert_equal "closed", data.fetch("sales")
  end

  test "configured live mode reports open sales and permits a manager outside the test operator list" do
    ENV["BILLING_MODE"] = "live"
    ENV["BILLING_TEST_OPERATOR_USER_IDS"] = ""
    ENV["STRIPE_LIVE_SECRET_KEY"] = "sk_live_stub"
    ENV["STRIPE_LIVE_PRICE_PRO_MONTHLY"] = "price_monthly"
    get "/api/v1/settings/billing", headers: bearer(@owner_token)
    assert_equal "open", data.fetch("sales")
    with_stripe(price: stripe_price.merge(livemode: true)) do
      post "/api/v1/settings/billing/checkout-session", params: billing_attributes, headers: bearer(@owner_token), as: :json
      assert_response :created
    end
  end

  test "disabled checkout answers 404 for a member before checking management access" do
    _, token, = signed_member
    Flags.with(:billing, false) do
      post "/api/v1/settings/billing/checkout-session", params: billing_attributes, headers: bearer(token), as: :json
      assert_error :not_found, "not_found"
    end
  end

  test "all protected billing endpoints require a session" do
    [ [ :get, "/api/v1/settings/billing" ], [ :post, "/api/v1/settings/billing/checkout-session" ],
      [ :post, "/api/v1/settings/billing/portal-session" ] ].each do |method, path|
      public_send(method, path, as: :json)
      assert_error :unauthorized, "unauthorized"
    end
  end

  test "members and viewers can read but cannot open checkout or portal" do
    [ [ "member", "full" ], [ "admin", "viewer" ] ].each do |role, access|
      _, token, = signed_member(role: role, access: access)
      get "/api/v1/settings/billing", headers: bearer(token)
      assert_response :ok
      assert_equal false, data.fetch("canManage")
      %w[checkout-session portal-session].each do |resource|
        post "/api/v1/settings/billing/#{resource}", params: billing_attributes, headers: bearer(token), as: :json
        assert_error :forbidden, "forbidden"
      end
    end
  end

  test "checkout guards run in the specified order without calling Stripe early" do
    stored = stored_subscription
    Net::HTTP.stub(:new, ->(*) { flunk "Guard must not call Stripe" }) do
      ENV["STRIPE_TEST_SECRET_KEY"] = "sk_live_wrong"
      ENV["BILLING_TEST_OPERATOR_USER_IDS"] = ""
      checkout_refusal :service_unavailable, "stripe_unavailable"
      ENV["STRIPE_TEST_SECRET_KEY"] = "sk_test_stub"
      checkout_refusal :forbidden, "test_mode"
      ENV["BILLING_TEST_OPERATOR_USER_IDS"] = @owner.id
      checkout_refusal :conflict, "already_subscribed", {}
      stored.destroy!
      checkout_refusal :unprocessable_entity, "offer_changed", { offerId: "unknown", accepted: false }
      checkout_refusal :unprocessable_entity, "offer_changed", { offerRevision: "old", accepted: false }
      checkout_refusal :unprocessable_entity, "not_accepted", { accepted: false }
      ENV.delete("STRIPE_TEST_PRICE_PRO_MONTHLY")
      checkout_refusal :service_unavailable, "stripe_unavailable"
    end
  end

  test "every mismatched Stripe price refuses checkout" do
    [ { unit_amount: 1901 }, { currency: "eur" }, { active: false }, { livemode: true },
      { recurring: { interval: "year", interval_count: 1 } }, { recurring: { interval: "month", interval_count: 2 } } ].each do |change|
      with_stripe(price: stripe_price.merge(change)) { checkout_refusal :unprocessable_entity, "price_mismatch" }
      assert_equal :get, @stripe_requests.last.fetch(:method)
    end
  end

  test "checkout returns 201 and sends agreed localized terms with stable idempotency" do
    @owner.update!(locale: "es")
    with_stripe do
      2.times do
        post "/api/v1/settings/billing/checkout-session", params: billing_attributes.merge(accepted: "true"),
          headers: bearer(@owner_token).merge("Accept-Language" => "en"), as: :json
        assert_response :created
        assert_equal({ "url" => "https://checkout.stripe.com/c/pay" }, data)
      end
      posts = @stripe_requests.select { |request| request[:method] == :post }
      assert_equal posts.first.dig(:headers, "Idempotency-Key"), posts.last.dig(:headers, "Idempotency-Key")
      form = posts.last.fetch(:form)
      assert_equal "true", form.fetch("allow_promotion_codes")
      assert_equal "false", form.fetch("adaptive_pricing[enabled]")
      refute form.keys.any? { |key| key.include?("tax") }
      assert_equal "es", form.fetch("locale")
      assert_equal I18n.t("billing.price_note", locale: :es), form.fetch("custom_text[submit][message]")
      assert_equal @organization.id, form.fetch("metadata[organization_id]")
      assert_equal @organization.id, form.fetch("subscription_data[metadata][organization_id]")
      assert_equal Billing.revision, form.fetch("metadata[offer_revision]")
      assert_equal "https://public.example/settings/billing?checkout=done", form.fetch("success_url")
      assert_equal "https://public.example/settings/billing", form.fetch("cancel_url")
      assert_equal "price_monthly", form.fetch("line_items[0][price]")
      travel 1.hour do
        post "/api/v1/settings/billing/checkout-session", params: billing_attributes, headers: bearer(@owner_token), as: :json
        assert_response :created
        refute_equal posts.first.dig(:headers, "Idempotency-Key"), @stripe_requests.last.dig(:headers, "Idempotency-Key")
      end
    end
    assert AuditEvent.exists?(action: "billing.checkout_started", actor_id: @owner.id, organization_id: @organization.id)
  end

  test "checkout idempotency changes with customer email locale and offer revision" do
    second = nil
    with_stripe do
      post "/api/v1/settings/billing/checkout-session", params: billing_attributes, headers: bearer(@owner_token), as: :json
      first = @stripe_requests.last.dig(:headers, "Idempotency-Key")
      @owner.update!(email: "changed-customer@example.com")
      post "/api/v1/settings/billing/checkout-session", params: billing_attributes, headers: bearer(@owner_token), as: :json
      changed_email = @stripe_requests.last.dig(:headers, "Idempotency-Key")
      refute_equal first, changed_email
      @owner.update!(locale: "es")
      post "/api/v1/settings/billing/checkout-session", params: billing_attributes, headers: bearer(@owner_token), as: :json
      second = @stripe_requests.last.dig(:headers, "Idempotency-Key")
      refute_equal first, second
    end
    revised = Billing.offers.map { |offer| offer.merge(amount_cents: offer[:amount_cents] + 1) }
    Billing.stub(:offers, revised) do
      with_stripe(price: stripe_price.merge(unit_amount: 1901)) do
        post "/api/v1/settings/billing/checkout-session", params: billing_attributes, headers: bearer(@owner_token), as: :json
        assert_response :created
        refute_equal second, @stripe_requests.last.dig(:headers, "Idempotency-Key")
      end
    end
  end

  test "provider failures and unsafe redirect URLs become stripe_unavailable" do
    %i[socket timeout http malformed].each do |failure|
      with_stripe(error: failure) { checkout_refusal :service_unavailable, "stripe_unavailable" }
    end
    [ "http://checkout.stripe.com/pay", "https://evil.example/pay", "https://checkout.stripe.com@evil.example/pay" ].each do |url|
      with_stripe(checkout_url: url) { checkout_refusal :service_unavailable, "stripe_unavailable" }
    end
  end

  test "subscription remains visible with billing off and portal can cancel" do
    stored_subscription
    Flags.with(:billing, false) do
      get "/api/v1/settings/billing", headers: bearer(@owner_token)
      assert_response :ok
      assert_equal "pro", data.fetch("plan")
      assert_equal "closed", data.fetch("sales")
      assert_equal true, data.dig("subscription", "paid")
      refute_includes response.body, "cus_paid"
      refute_includes response.body, "sub_paid"
      with_stripe do
        post "/api/v1/settings/billing/portal-session", headers: bearer(@owner_token), as: :json
        assert_response :created
        assert_equal({ "url" => "https://billing.stripe.com/p/session" }, data)
        assert_equal "cus_paid", @stripe_requests.last.dig(:form, "customer")
        assert_equal "https://public.example/settings/billing", @stripe_requests.last.dig(:form, "return_url")
      end
    end
    assert AuditEvent.exists?(action: "billing.portal_opened", organization_id: @organization.id)
    ENV.delete("STRIPE_TEST_SECRET_KEY")
    post "/api/v1/settings/billing/portal-session", headers: bearer(@owner_token), as: :json
    assert_error :service_unavailable, "stripe_unavailable"
  end

  test "paid status is restricted to future unpaused active trialing and past_due subscriptions" do
    subscription = stored_subscription
    [ [ "active", false, 1.day.from_now, true ], [ "trialing", false, 1.day.from_now, true ],
      [ "past_due", false, 1.day.from_now, true ], [ "active", true, 1.day.from_now, false ],
      [ "canceled", false, 1.day.from_now, false ], [ "active", false, 1.day.ago, false ],
      [ "active", false, nil, false ] ].each do |status, paused, ending, paid|
      subscription.update!(status: status, paused: paused, current_period_end: ending)
      get "/api/v1/settings/billing", headers: bearer(@owner_token)
      assert_equal paid, data.dig("subscription", "paid")
      assert_equal paid ? "pro" : "free", data.fetch("plan")
    end
  end

  test "billing off to checkout to paid webhook to paid overview flow" do
    Flags.with(:billing, false) do
      get "/api/v1/settings/billing", headers: bearer(@owner_token)
      assert_error :not_found, "not_found"
    end
    get "/api/v1/settings/billing", headers: bearer(@owner_token)
    assert_response :ok
    revision = data.fetch("offerRevision")
    with_stripe do
      post "/api/v1/settings/billing/checkout-session", params: billing_attributes.merge(offerRevision: revision), headers: bearer(@owner_token), as: :json
      assert_response :created
      assert data.fetch("url").start_with?("https://checkout.stripe.com/")
      assert_enqueued_with(job: ProcessStripeEventJob, queue: "default") { deliver_webhook }
      assert_response :ok
      assert_equal({ "received" => true }, data)
      perform_enqueued_jobs(only: ProcessStripeEventJob)
    end
    get "/api/v1/settings/billing", headers: bearer(@owner_token)
    assert_response :ok
    assert_equal "pro", data.fetch("plan")
    assert_equal true, data.dig("subscription", "paid")
    assert_equal "synced", BillingEvent.find_by!(stripe_event_id: "evt_paid").outcome
    assert AuditEvent.exists?(action: "billing.subscription_changed", organization_id: @organization.id)
  end

  test "configured plans and intervals have bilingual copy and prices never mention extra charges" do
    reference = TranslationCatalog.reference_rows
    keys = Billing.config.fetch(:plans).keys.flat_map { |plan| [ "billing.plan.#{plan}", "billing.plan_summary.#{plan}" ] } +
      Billing.offers.map { |offer| offer[:interval] }.uniq.flat_map { |interval| [ "billing.interval.#{interval}", "billing.per.#{interval}" ] }
    keys.each do |key|
      TranslationCatalog.locales.each { |locale| assert reference.fetch(key).fetch(locale).present?, "#{key} #{locale}" }
    end
    refute_match(/\b(?:tax|VAT|GST|impuesto|IVA)\b/i, File.read(Rails.root.join("i18n/translations.csv")))
  end

  private

  def checkout_refusal(status, code, changes = {})
    post "/api/v1/settings/billing/checkout-session", params: billing_attributes.merge(changes), headers: bearer(@owner_token), as: :json
    assert_error status, code
  end
end
