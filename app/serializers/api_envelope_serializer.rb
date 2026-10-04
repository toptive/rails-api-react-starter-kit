class ApiEnvelopeSerializer
  include ApplicationSerializer

  typelize response: "Envelope<unknown>"
  hash_attributes :response
end
