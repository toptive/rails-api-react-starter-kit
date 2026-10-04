class ApiErrorBodySerializer
  include ApplicationSerializer

  typelize code: :string, message: :string, details: "Record<string, unknown>"
  hash_attributes :code, :message, :details
end
