class LegalDocumentVersionSerializer
  include ApplicationSerializer

  typelize id: :string, number: :number, note: [ :string, nullable: true ],
    published_at: [ :string, nullable: true ], inserted_at: :string,
    titles: "Record<string, string>", bodies: "Record<string, string>"
  attributes :id, :number, :note
  attribute(:titles) { |version| version.titles }
  attribute(:bodies) { |version| version.bodies }
  attribute(:published_at) { |version| version.published_at&.utc&.iso8601 }
  attribute(:inserted_at) { |version| version.created_at.utc.iso8601 }
end
