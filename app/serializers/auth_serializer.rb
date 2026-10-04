class AuthSerializer
  include ApplicationSerializer

  typelize user: {}
  one :user, resource: UserSerializer
  typelize impersonator: { nullable: true }
  one :impersonator, resource: UserSerializer
  typelize organization: "null", membership: "null", organizations: "never[]",
    superadmin: :boolean, onboarding_required: :boolean, session_id: :string,
    sudo_until: [ :string, nullable: true ]
  hash_attributes :organization, :membership, :organizations, :superadmin, :onboarding_required, :session_id
  attribute(:sudo_until) { |payload| payload.fetch(:sudo_until)&.utc&.iso8601 }
end
