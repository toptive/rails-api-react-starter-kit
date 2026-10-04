class Billing::Reconciliation
  def process(id)
    event = BillingEvent.find_by(id: id)
    return unless event && !event.processed_at

    # Network calls stay outside database locks.
    stripe = Billing::Gateway.new(Billing.require_key!).get("subscriptions/#{event.stripe_subscription_id}") if event.stripe_subscription_id && event.livemode == Billing.livemode?
    event.with_lock do
      return if event.processed_at

      outcome = if event.livemode != Billing.livemode?
        "wrong_mode"
      elsif stripe.nil?
        "no_subscription"
      else
        sync(stripe, event)
      end
      event.update!(processed_at: Time.current, outcome: outcome)
    end
  end

  private

  def sync(stripe, event)
    return "wrong_mode" unless stripe["livemode"] == Billing.livemode?

    organization_id = stripe.dig("metadata", "organization_id") || event.organization_id
    return "unknown_organization" unless organization_id.is_a?(String) && organization_id.match?(Billing::Webhook::UUID)

    organization = Organization.find_by(id: organization_id)
    return "unknown_organization" unless organization

    scope = Session::Scope.new(organization: organization)
    organization.with_lock do
      existing = BillingSubscription.for(scope).find_by(livemode: Billing.livemode?)
      attributes = attributes_for(stripe, event)
      incoming = BillingSubscription.for(scope).new(attributes)
      return "kept_paid_subscription" if existing && existing.stripe_subscription_id != incoming.stripe_subscription_id && existing.paid? && !incoming.paid?

      was_paid = existing&.paid? || false
      changed = !existing || existing.plan != incoming.plan || existing.status != incoming.status
      subscription = existing || BillingSubscription.for(scope).new
      subscription.update!(attributes)
      if changed
        Audit.record("billing.subscription_changed", scope: scope, subject: subscription,
          metadata: attributes.slice(:plan, :status, :offer_id))
      end
      funnel = if !was_paid && subscription.paid?
        "subscription_started"
      elsif was_paid && !subscription.paid?
        "subscription_canceled"
      end
      if funnel
        offer = Billing.offers.find { |candidate| candidate[:id] == subscription.offer_id }
        properties = { plan: subscription.plan, interval: offer&.fetch(:interval), mode: Billing.mode }
        ActiveRecord.after_all_transactions_commit { Analytics.track(funnel, nil, properties) }
      end
      "synced"
    end
  end

  def attributes_for(stripe, event)
    item = stripe.dig("items", "data")&.first || {}
    price = item.dig("price", "id")
    offer = Billing.offers.find { |candidate| Billing.price_id(candidate) == price } if price.present?
    ending = item["current_period_end"] || stripe["current_period_end"]
    customer = stripe["customer"].is_a?(Hash) ? stripe.dig("customer", "id") : stripe["customer"]
    valid = stripe["id"] == event.stripe_subscription_id && customer.is_a?(String) && customer.start_with?("cus_") &&
      stripe["status"].is_a?(String) && (ending.nil? || ending.is_a?(Integer))
    raise ApiError.unavailable(:stripe_unavailable) unless valid

    { livemode: stripe["livemode"], stripe_customer_id: customer, stripe_subscription_id: stripe["id"],
      offer_id: offer&.fetch(:id), plan: offer&.fetch(:plan) || Billing.default_plan,
      status: stripe["status"], current_period_end: ending && Time.at(ending).utc,
      cancel_at_period_end: stripe["cancel_at_period_end"] == true,
      paused: stripe["pause_collection"].present? || stripe["status"] == "paused" }
  end
end
