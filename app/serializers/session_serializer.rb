class SessionSerializer
  include ApplicationSerializer

  typelize id: :string, user_agent: [ :string, nullable: true ], ip_address: [ :string, nullable: true ],
    authenticated_at: [ :string, nullable: true ], inserted_at: :string, current: :boolean
  attributes :id, :user_agent, :ip_address
  attribute(:authenticated_at) { |session| session.authenticated_at&.utc&.iso8601 }
  attribute(:inserted_at) { |session| session.created_at.utc.iso8601 }
  attribute(:current) { |session| session.id == params.fetch(:current_session_id) }
end
