class TranslationValueSerializer
  include ApplicationSerializer

  typelize locale: :string, value: :string, edited: :boolean
  hash_attributes :locale, :value, :edited
end
