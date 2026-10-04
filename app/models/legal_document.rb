class LegalDocument < ApplicationRecord
  SLUGS = %w[terms privacy cookies].freeze
  has_many :versions, -> { order(number: :desc) }, class_name: "LegalDocumentVersion", inverse_of: :legal_document
  belongs_to :published_version, class_name: "LegalDocumentVersion", optional: true
  validates :slug, inclusion: { in: SLUGS }, uniqueness: true

  def self.ensure_documents!
    insert_all(SLUGS.map { |slug| { slug: slug } }, unique_by: :slug)
  end

  def self.admin_list
    ensure_documents!
    includes(:versions).order(:slug).to_a
  end

  def self.admin_detail(slug)
    raise ApiError.not_found unless SLUGS.include?(slug)

    ensure_documents!
    includes(:versions).find_by!(slug: slug)
  end

  def self.create_version!(slug, attributes, scope, request)
    User::Input.validate!(attributes, string_fields: [ :note ], boolean_fields: [ :publish ])
    document = admin_detail(slug)
    document.with_lock do
      version = document.versions.create!(attributes.slice(:titles, :bodies, :note).merge(
        number: (document.versions.maximum(:number) || 0) + 1, created_by_id: scope.user.id))
      Audit.record("legal.version_created", scope: scope, subject: version,
        metadata: { slug: slug, number: version.number }, request: request)
      document.publish!(version, scope, request) if ActiveModel::Type::Boolean.new.cast(attributes[:publish])
      version
    end
  end

  def self.publish_version!(slug, number, scope, request)
    raise ApiError.not_found unless number.to_s.match?(/\A[1-9]\d*\z/)

    document = admin_detail(slug)
    document.with_lock do
      version = document.versions.find_by!(number: number.to_i)
      document.publish!(version, scope, request)
    end
    admin_detail(slug)
  end

  def publish!(version, scope, request)
    return if published_version_id == version.id

    version.update!(published_at: Time.current)
    update!(published_version: version)
    Audit.record("legal.published", scope: scope, subject: version,
      metadata: { slug: slug, number: version.number }, request: request)
  end

  def self.public_page(slug, locale)
    document = includes(:published_version).find_by!(slug: slug)
    version = document.published_version
    raise ApiError.not_found unless version

    { slug: slug, title: version.localized(:titles, locale), body: version.localized(:bodies, locale),
      version: version.number, published_at: version.published_at, etag: %Q("#{slug}:#{version.number}:#{locale}") }
  end
end
