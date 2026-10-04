class AuthSerializer
  include ApplicationSerializer

  typelize user: {}
  one :user, resource: UserSerializer
  typelize impersonator: { nullable: true }
  one :impersonator, resource: UserSerializer
  typelize organization: {}, membership: {}, organizations: {}
  one :organization, resource: OrganizationSerializer
  one :membership, resource: MembershipSerializer, params: { bootstrap: true }
  many :organizations, resource: OrganizationSerializer
  typelize superadmin: :boolean, onboarding_required: :boolean, session_id: :string,
    sudo_until: [ :string, nullable: true ]
  hash_attributes :superadmin, :onboarding_required, :session_id
  attribute(:sudo_until) { |payload| payload.fetch(:sudo_until)&.utc&.iso8601 }
end
