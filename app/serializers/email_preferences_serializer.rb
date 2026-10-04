class EmailPreferencesSerializer
  include ApplicationSerializer

  typelize optional_emails: :boolean
  attributes :optional_emails
end
