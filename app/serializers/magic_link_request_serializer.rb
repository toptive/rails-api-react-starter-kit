class MagicLinkRequestSerializer
  include ApplicationSerializer

  typelize email: :string, new_account: :boolean
  hash_attributes :email, :new_account
end
