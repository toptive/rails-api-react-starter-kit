class AccountDeletionSerializer
  include ApplicationSerializer

  typelize blocker: [ "{ reason: #{literal(AccountDeletion::REASONS)}; organization: string }", nullable: true ]
  hash_attributes :blocker
end
