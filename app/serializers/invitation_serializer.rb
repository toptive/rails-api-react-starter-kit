class InvitationSerializer
  include ApplicationSerializer

  typelize id: :string, email: :string, role: literal(Membership::ROLES), access: literal(Membership::ACCESSES),
    expires_at: :string, inserted_at: :string
  attributes :id, :email, :role, :access
  attribute(:expires_at) { |invitation| invitation.expires_at.utc.iso8601 }
  attribute(:inserted_at) { |invitation| invitation.created_at.utc.iso8601 }
end
