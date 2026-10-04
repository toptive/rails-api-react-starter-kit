class RedirectUrlSerializer
  include ApplicationSerializer

  typelize url: :string
  hash_attributes :url
end
