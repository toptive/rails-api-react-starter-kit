class MagicLinkSerializer
  include ApplicationSerializer

  typelize email: :string, confirmed: :boolean
  hash_attributes :email, :confirmed
end
