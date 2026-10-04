class WebhookReceiptSerializer
  include ApplicationSerializer

  typelize received: :boolean
  hash_attributes :received
end
