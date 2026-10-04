class OrganizationSettingsSerializer
  include ApplicationSerializer

  typelize organization: {}
  one :organization, resource: OrganizationSerializer
  typelize can_edit: :boolean
  hash_attributes :can_edit
end
