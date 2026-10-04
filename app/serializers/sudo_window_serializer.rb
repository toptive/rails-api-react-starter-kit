class SudoWindowSerializer
  include ApplicationSerializer

  typelize sudo_until: :string
  attribute(:sudo_until) { |session| session.sudo_until.utc.iso8601 }
end
