class TranslationEntrySerializer
  include ApplicationSerializer

  typelize key: :string
  hash_attributes :key
  typelize values: {}
  many :values, resource: TranslationValueSerializer
end
