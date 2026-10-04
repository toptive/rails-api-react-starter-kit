class AdminStatsSerializer
  include ApplicationSerializer

  typelize users: :number, organizations: :number
  hash_attributes :users, :organizations
end
