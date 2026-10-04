class TurnstileSerializer
  include ApplicationSerializer

  typelize required: :boolean, site_key: [ :string, nullable: true ]
  hash_attributes :required, :site_key
end
