class SubscriptionSerializer
  include ApplicationSerializer

  typelize plan: :string, offer_id: [ :string, nullable: true ], status: :string, cancel_at_period_end: :boolean, paused: :boolean
  attributes :plan, :offer_id, :status, :cancel_at_period_end, :paused
  typelize current_period_end: [ :string, nullable: true ], paid: :boolean
  attribute(:current_period_end) { |subscription| subscription.current_period_end&.utc&.iso8601 }
  attribute(:paid) { |subscription| subscription.paid? }
end
