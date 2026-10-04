class MembershipSerializer
  include ApplicationSerializer

  typelize id: :string, role: literal(Membership::ROLES), access: literal(Membership::ACCESSES), inserted_at: :string
  attributes :id, :role, :access
  attribute(:inserted_at) { |membership| membership.created_at.utc.iso8601 }
  typelize user: { nullable: true }
  one :user, resource: UserSerializer, source: ->(params) { user unless params[:bootstrap] }
end
