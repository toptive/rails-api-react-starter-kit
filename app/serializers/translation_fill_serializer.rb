class TranslationFillSerializer
  include ApplicationSerializer

  typelize count: :number
  hash_attributes :count
end
