class FieldErrorSerializer
  include ApplicationSerializer

  typelize key: :string, message: :string, bindings: [ "Record<string, string | number>", optional: true ]
  hash_attributes :key, :message, :bindings
end
