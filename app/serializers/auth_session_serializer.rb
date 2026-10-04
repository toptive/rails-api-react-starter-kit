class AuthSessionSerializer
  include ApplicationSerializer

  typelize token: [ :string, nullable: true ], expires_at: :string,
    sudo_until: [ :string, nullable: true ], new_account: :boolean
  hash_attributes :token, :new_account
  attribute(:expires_at) { |payload| payload.fetch(:expires_at).utc.iso8601 }
  attribute(:sudo_until) { |payload| payload.fetch(:sudo_until)&.utc&.iso8601 }
  typelize user: {}
  one :user, resource: UserSerializer
  typelize impersonator: { nullable: true }
  one :impersonator, resource: UserSerializer
end
