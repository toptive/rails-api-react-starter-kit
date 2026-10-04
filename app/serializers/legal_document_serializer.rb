class LegalDocumentSerializer
  include ApplicationSerializer

  typelize id: :string, slug: :string, published_version_id: [ :string, nullable: true ]
  attributes :id, :slug, :published_version_id
  typelize versions: {}
  many :versions, resource: LegalDocumentVersionSerializer
end
