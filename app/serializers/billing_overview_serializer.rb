class BillingOverviewSerializer
  include ApplicationSerializer

  typelize plan: :string, offer_revision: :string, sales: literal(Billing::SALES), can_manage: :boolean
  hash_attributes :plan, :offer_revision, :sales, :can_manage
  typelize subscription: { nullable: true }
  one :subscription, resource: SubscriptionSerializer
  many :offers, resource: OfferSerializer
end
