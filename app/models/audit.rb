class Audit
  def self.record(action, actor: nil, session: nil, scope: nil, subject: nil, metadata: {}, request: nil)
    session ||= scope&.session
    actor ||= scope&.user
    AuditEvent.create!(action: action, actor_id: actor&.id || session&.user_id,
      impersonator_id: session&.impersonator_user_id, organization_id: scope&.organization&.id || session&.organization_id, subject_type: subject&.class&.name,
      subject_id: subject&.id, metadata: metadata, ip_address: request&.remote_ip || session&.ip_address)
  end
end
