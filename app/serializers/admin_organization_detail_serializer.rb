class AdminOrganizationDetailSerializer
  include ApplicationSerializer

  typelize organization: {}
  one :organization, resource: OrganizationSerializer
  typelize memberships: {}
  many :memberships, resource: MembershipSerializer
end
