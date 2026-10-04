class LegalPageSerializer
  include ApplicationSerializer

  typelize slug: :string, title: :string, body: :string, version: :number, published_at: :string
  hash_attributes :slug, :title, :body, :version
  attribute(:published_at) { |page| page.fetch(:published_at).utc.iso8601 }
end
