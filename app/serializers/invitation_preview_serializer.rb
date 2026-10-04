class InvitationPreviewSerializer
  include ApplicationSerializer

  typelize organization: :string, email: :string, role: literal(Membership::ROLES), access: literal(Membership::ACCESSES),
    email_matches: :boolean, expires_at: :string
  hash_attributes :organization, :email, :role, :access, :email_matches
  attribute(:expires_at) { |preview| preview.fetch(:expires_at).utc.iso8601 }
end
