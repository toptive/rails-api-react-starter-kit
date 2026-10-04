class AdminOrganizationSerializer
  include ApplicationSerializer

  typelize id: :string, name: :string, slug: :string, members: :number, inserted_at: :string
  attributes :id, :name, :slug
  attribute(:members) { |organization| organization.admin_member_count }
  attribute(:inserted_at) { |organization| organization.created_at.utc.iso8601 }
end
