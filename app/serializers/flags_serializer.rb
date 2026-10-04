class FlagsSerializer
  include ApplicationSerializer

  typelize billing: :boolean
  hash_attributes :billing
end
