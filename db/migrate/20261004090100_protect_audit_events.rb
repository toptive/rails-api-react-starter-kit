class ProtectAuditEvents < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION reject_audit_event_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'audit_events are append-only';
      END;
      $$;
      CREATE TRIGGER audit_events_append_only BEFORE UPDATE OR DELETE ON audit_events
        FOR EACH ROW EXECUTE FUNCTION reject_audit_event_mutation();
    SQL
  end

  def down
    execute "DROP TRIGGER audit_events_append_only ON audit_events"
    execute "DROP FUNCTION reject_audit_event_mutation()"
  end
end
