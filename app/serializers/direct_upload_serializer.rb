class DirectUploadSerializer
  include ApplicationSerializer

  typelize url: :string, key: :string, method: '"PUT"', headers: "Record<string, string>"
  hash_attributes :url, :key, :method
  attribute(:headers) { |payload| payload.fetch(:headers) }
end
