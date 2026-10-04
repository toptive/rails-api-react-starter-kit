class AdminUserDetailSerializer
  include ApplicationSerializer

  typelize user: {}
  one :user, resource: UserSerializer
  typelize organizations: {}
  many :organizations, resource: OrganizationSerializer
end
