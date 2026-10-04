class EmailSubscriptionSerializer
  include ApplicationSerializer

  typelize email: :string, subscribed: :boolean
  hash_attributes :email, :subscribed
end
