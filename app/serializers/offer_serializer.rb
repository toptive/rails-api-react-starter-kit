class OfferSerializer
  include ApplicationSerializer

  typelize id: :string, plan: :string, interval: literal(%w[month year]), amount_cents: :number, currency: :string
  hash_attributes :id, :plan, :interval, :amount_cents, :currency
end
