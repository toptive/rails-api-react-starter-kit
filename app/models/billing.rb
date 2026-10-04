class Billing
  SALES = %w[open test closed].freeze

  def self.config = @config ||= Rails.application.config_for(:billing).deep_symbolize_keys
  def self.mode = ENV.fetch("BILLING_MODE", "test")
  def self.livemode? = mode == "live"
  def self.default_plan = config.fetch(:default_plan)
  def self.offers = config.fetch(:offers).map { |offer| offer.reverse_merge(currency: config.fetch(:currency)) }
  def self.revision = Digest::SHA256.hexdigest(JSON.generate(offers.sort_by { |offer| offer.fetch(:id) }))[0, 16]
  def self.price_id(offer) = ENV["STRIPE_#{mode.upcase}_PRICE_#{offer.fetch(:id).upcase}"].presence
  def self.webhook_secret = ENV["STRIPE_#{mode.upcase}_WEBHOOK_SECRET"].presence

  def self.secret_key
    key = ENV["STRIPE_#{mode.upcase}_SECRET_KEY"]
    key if key&.match?(/\A(?:sk|rk)_#{mode}_\S+\z/)
  end

  def self.require_key!
    secret_key || raise(ApiError.unavailable(:stripe_unavailable))
  end

  def self.operator?(scope)
    scope.session&.superadmin? || ENV.fetch("BILLING_TEST_OPERATOR_USER_IDS", "").split(",").map(&:strip).include?(scope.user&.id)
  end

  def self.sales(scope)
    return "closed" unless Flags.enabled?(:billing) && secret_key
    return "closed" if !livemode? && !operator?(scope)

    livemode? ? "open" : "test"
  end

  def self.current(scope) = BillingSubscription.for(scope).find_by(livemode: livemode?)
  def self.plan(scope) = current(scope)&.then { |subscription| subscription.paid? ? subscription.plan : default_plan } || default_plan

  def self.overview(scope)
    subscription = current(scope)
    raise ApiError.not_found unless Flags.enabled?(:billing) || subscription

    { plan: subscription&.paid? ? subscription.plan : default_plan, subscription: subscription,
      offers: offers, offer_revision: revision, sales: sales(scope),
      can_manage: BillingPolicy.new(scope, self).create? }
  end

  def self.require_enabled!
    raise ApiError.not_found unless Flags.enabled?(:billing)
  end

  def self.checkout(scope, attributes, request)
    offer, price, key, form = scope.organization.with_lock do
      require_enabled!
      require_key!
      raise ApiError.forbidden(:test_mode) unless livemode? || operator?(scope)

      Organization.refresh_membership!(scope)
      Pundit.authorize(scope, self, :create?)
      raise ApiError.conflict(:already_subscribed) if current(scope)&.paid?

      offer = offers.find { |candidate| candidate[:id] == attributes[:offer_id] }
      raise ApiError.unprocessable(:offer_changed) unless offer && attributes[:offer_revision] == revision
      raise ApiError.unprocessable(:not_accepted) unless [ true, "true" ].include?(attributes[:accepted])

      price = price_id(offer)
      raise ApiError.unavailable(:stripe_unavailable) unless price&.match?(/\Aprice_[a-zA-Z0-9_]+\z/) && !price.include?("CHANGE_ME")

      locale = scope.user.locale
      key = Digest::SHA256.hexdigest([ scope.organization.id, scope.user.id, scope.user.email, offer[:id], revision, locale, Time.current.to_i / 3600 ].join(":"))
      [ offer, price, key, checkout_form(scope, offer, price, locale) ]
    end
    gateway = Gateway.new(require_key!)
    fetched = gateway.get("prices/#{price}")
    matches = fetched["active"] == true && fetched["livemode"] == livemode? &&
      fetched["unit_amount"] == offer[:amount_cents] && fetched["currency"] == offer[:currency] &&
      fetched.dig("recurring", "interval") == offer[:interval] && fetched.fetch("recurring", {}).fetch("interval_count", 1) == 1
    unless matches
      Rails.logger.error("Stripe price does not match the configured offer")
      raise ApiError.unprocessable(:price_mismatch)
    end
    session = gateway.post("checkout/sessions", form, idempotency_key: "checkout-v1-#{key}")
    result = { url: checked_url(session["url"], "checkout.stripe.com") }
    scope.organization.with_lock do
      Audit.record("billing.checkout_started", scope: scope, subject: scope.organization,
        metadata: { offer_id: offer[:id], offer_revision: revision, mode: mode }, request: request)
    end
    Analytics.track("checkout_started", scope, offer.slice(:plan, :interval).merge(mode: mode))
    result
  end

  def self.checkout_form(scope, offer, price, locale)
    base = public_url
    { mode: "subscription", line_items: [ { price: price, quantity: 1 } ],
      success_url: "#{base}/settings/billing?checkout=done", cancel_url: "#{base}/settings/billing",
      client_reference_id: scope.organization.id, customer_email: scope.user.email, locale: locale,
      allow_promotion_codes: true, payment_method_collection: "if_required", adaptive_pricing: { enabled: false },
      custom_text: { submit: { message: I18n.t("billing.price_note", locale: locale) } },
      metadata: { organization_id: scope.organization.id, offer_id: offer[:id], offer_revision: revision },
      subscription_data: { metadata: { organization_id: scope.organization.id, offer_id: offer[:id] } } }
  end
  private_class_method :checkout_form

  def self.portal(scope, request)
    subscription, form = scope.organization.with_lock do
      Organization.refresh_membership!(scope)
      Pundit.authorize(scope, self, :create?)
      subscription = current(scope)
      raise ApiError.conflict(:no_subscription) unless subscription

      require_key!
      [ subscription, { customer: subscription.stripe_customer_id,
        return_url: "#{public_url}/settings/billing", locale: scope.user.locale } ]
    end
    result = Gateway.new(require_key!).post("billing_portal/sessions", form)
    url = checked_url(result["url"], "billing.stripe.com")
    scope.organization.with_lock do
      Audit.record("billing.portal_opened", scope: scope, subject: subscription, request: request)
    end
    { url: url }
  end

  def self.public_url = (ENV["PUBLIC_URL"].presence || Rails.application.config.x.spa_origin).delete_suffix("/")

  def self.checked_url(url, host)
    uri = URI.parse(url.to_s)
    stub = Rails.env.test? && ENV["E2E_STRIPE_URL"].present? && URI(ENV.fetch("E2E_STRIPE_URL"))
    allowed_stub = stub && [ uri.scheme, uri.host, uri.port ] == [ stub.scheme, stub.host, stub.port ]
    allowed_stripe = uri.scheme == "https" && uri.host == host && uri.port == 443
    raise ApiError.unavailable(:stripe_unavailable) unless uri.userinfo.nil? && (allowed_stripe || allowed_stub)

    url
  rescue URI::InvalidURIError
    raise ApiError.unavailable(:stripe_unavailable)
  end
  private_class_method :checked_url

  def self.limit(scope, key)
    return unless Flags.enabled?(:billing)

    config.fetch(:plans).fetch(plan(scope).to_sym).fetch(key)
  end

  def self.with_capacity(scope, key, count:, &write)
    scope.organization.with_lock do
      maximum = limit(scope, key)
      raise ApiError.unprocessable(:limit_reached, { limit: key, maximum: maximum }) if maximum && count.call >= maximum

      write.call
    end
  end

  def self.receive(raw, signature) = Webhook.new.receive(raw, signature)
  def self.process_event(id) = Reconciliation.new.process(id)
  def self.notice_sweep = Notices.new.sweep
  def self.purge_events = BillingEvent.where("processed_at < ?", 30.days.ago).delete_all

  def self.readiness
    problems = []
    problems << "BILLING_MODE must be test or live" unless %w[test live].include?(mode)
    problems << "Stripe key is missing or belongs to another mode" unless secret_key
    problems << "Stripe webhook secret is missing" unless webhook_secret&.start_with?("whsec_")
    plans = config.fetch(:plans)
    offers.each do |offer|
      problems << "Offer #{offer[:id]} has no valid Stripe price" unless price_id(offer)&.start_with?("price_") && !price_id(offer).include?("CHANGE_ME")
      problems << "Offer #{offer[:id]} uses an unknown plan" unless plans.key?(offer[:plan].to_sym)
    end
    problems << "Plans must declare the same limits" unless plans.values.map(&:keys).map(&:sort).uniq.one?
    problems
  end
end
