class OrganizationSerializer
  include ApplicationSerializer

  typelize id: :string, name: :string, slug: :string, personal: :boolean
  attributes :id, :name, :slug, :personal
end
