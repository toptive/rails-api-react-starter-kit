class AuditEvent < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  def self.admin_list(query)
    records = includes(:actor).order(created_at: :desc, id: :desc)
    if query.to_s.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)
      records = records.where("actor_id = :id OR subject_id = :id", id: query)
    elsif query.present?
      records = records.where("action ILIKE ?", "%#{sanitize_sql_like(query)}%")
    end
    records
  end
  def readonly? = persisted?
end
