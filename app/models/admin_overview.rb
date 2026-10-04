class AdminOverview
  def self.stats = { users: User.count, organizations: Organization.count }
end
