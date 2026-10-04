class AuditEventSerializer
  include ApplicationSerializer

  typelize id: :string, action: :string, actor_id: [ :string, nullable: true ],
    impersonator_id: [ :string, nullable: true ], organization_id: [ :string, nullable: true ],
    subject_type: [ :string, nullable: true ], subject_id: [ :string, nullable: true ],
    metadata: "Record<string, unknown>", inserted_at: :string, actor_email: [ :string, nullable: true ]
  attributes :id, :action, :actor_id, :impersonator_id, :organization_id, :subject_type, :subject_id
  attribute(:metadata) { |event| event.metadata }
  attribute(:inserted_at) { |event| event.created_at.utc.iso8601 }
  attribute(:actor_email) { |event| event.actor&.email }
end
