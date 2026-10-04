class Billing::Notices
  def sweep
    return unless Flags.enabled?(:billing_renewal_notices) && Billing.secret_key

    Organization.find_each do |organization|
      scope = Session::Scope.new(organization: organization)
      subscription = Billing.current(scope)
      next unless due?(subscription)

      preview = Billing::Gateway.new(Billing.require_key!).post("invoices/create_preview", subscription: subscription.stripe_subscription_id)
      raise ApiError.unavailable(:stripe_unavailable) unless preview["amount_due"].is_a?(Integer) && preview["currency"].is_a?(String)

      claim(scope, subscription, preview)
    rescue ApiError => error
      Monitoring.report(error)
    end
  end

  private

  def due?(subscription)
    return false unless subscription && %w[active trialing].include?(subscription.status) && !subscription.cancel_at_period_end? && !subscription.paused?
    return false unless subscription.current_period_end && subscription.renewal_notice_sent_for != subscription.current_period_end

    offer = Billing.offers.find { |candidate| candidate[:id] == subscription.offer_id }
    config = Billing.config
    offer && config.fetch(:renewal_notice_intervals).include?(offer[:interval]) &&
      subscription.current_period_end.between?(config.dig(:renewal_notice_days, :until).days.from_now, config.dig(:renewal_notice_days, :from).days.from_now)
  end

  def claim(scope, subscription, preview)
    scope.organization.with_lock do
      period = subscription.current_period_end
      subscription = BillingSubscription.for(scope).find(subscription.id)
      return unless subscription.current_period_end == period && due?(subscription)

      AccountMail.require_available!
      subscription.update!(renewal_notice_sent_for: subscription.current_period_end)
      Membership.for(scope).includes(:user).where(role: %w[owner admin], access: "full").each do |membership|
        RenewalNoticeDeliveryJob.perform_later(scope.organization.id, subscription.id, membership.user_id, preview.slice("amount_due", "currency"))
      end
      Audit.record("billing.renewal_notice_queued", scope: scope, subject: subscription,
        metadata: { amount_cents: preview["amount_due"], currency: preview["currency"] })
    end
  end
end
