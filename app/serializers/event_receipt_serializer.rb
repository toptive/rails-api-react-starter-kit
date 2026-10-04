class EventReceiptSerializer
  include ApplicationSerializer

  typelize accepted: :boolean
  hash_attributes :accepted
end
