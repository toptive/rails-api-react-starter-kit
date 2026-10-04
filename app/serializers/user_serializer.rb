class UserSerializer
  include ApplicationSerializer

  typelize id: :string, name: :string, email: :string, role: literal(User::ROLES), locale: :string,
    confirmed_at: [ :string, nullable: true ], inserted_at: :string, has_password: :boolean
  attributes :id, :name, :email, :role, :locale
  attribute(:confirmed_at) { |user| user.confirmed_at&.utc&.iso8601 }
  attribute(:inserted_at) { |user| user.created_at.utc.iso8601 }
  attribute(:has_password) { |user| user.has_password? }
end
