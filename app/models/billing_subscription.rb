class BillingSubscription < ApplicationRecord
  include TenantScoped

  CLOSED_STATUSES = %w[canceled incomplete_expired].freeze
  PAID_STATUSES = %w[active trialing past_due].freeze
  validates :status, :plan, :stripe_customer_id, :stripe_subscription_id, presence: true
  validates :livemode, inclusion: { in: [ true, false ] }

  def self.open?(scope) = self.for(scope).where.not(status: CLOSED_STATUSES).exists?
  def paid? = PAID_STATUSES.include?(status) && !paused? && current_period_end.present? && current_period_end > Time.current
end
