class EnvelopeSerializer
  include ApplicationSerializer

  typelizer_config { self.types_global = Typelizer::DEFAULT_TYPES_GLOBAL + %w[T M] }
  typelize data: "T", meta: [ "M", optional: true ]
  hash_attributes :data, :meta
end
