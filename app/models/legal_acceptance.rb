class LegalAcceptance < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :legal_document_version, optional: true

  def self.at_signup!(user, ip_address)
    documents = LegalDocument.where(slug: %w[terms privacy]).order(:slug).lock.to_a
    published = documents.filter_map { |document| document.published_version&.then { |version| [ document.slug, version ] } }
    versions = published.to_h { |slug, version| [ slug, version.number ] }
    user.update!(legal_accepted_at: Time.current, legal_accepted_ip_address: ip_address, legal_accepted_versions: versions)
    common = { user: user, email_hash: Digest::SHA256.hexdigest(user.email.downcase), ip_address: ip_address, accepted_at: user.legal_accepted_at }
    if published.empty?
      create!(common.merge(versions: {}))
    else
      published.each do |slug, version|
        create!(common.merge(legal_document_version: version, versions: { slug => version.number }))
      end
    end
    versions.keys
  end
end
