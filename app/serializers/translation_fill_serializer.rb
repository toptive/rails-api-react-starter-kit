class TranslationFillSerializer
  include ApplicationSerializer

  typelize count: [ :number, nullable: true ]
  hash_attributes :count
end
