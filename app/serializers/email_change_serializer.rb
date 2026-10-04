class EmailChangeSerializer
  include ApplicationSerializer

  typelize email: :string
  hash_attributes :email
end
