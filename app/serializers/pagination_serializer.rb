class PaginationSerializer
  include ApplicationSerializer

  typelize page: :number, per_page: :number, total: :number, total_pages: :number
  hash_attributes :page, :per_page, :total, :total_pages
end
