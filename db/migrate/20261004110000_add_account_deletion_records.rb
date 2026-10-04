class AddAccountDeletionRecords < ActiveRecord::Migration[8.1]
  def up
    create_table :subscriptions, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: { on_delete: :restrict }
      t.boolean :livemode, null: false, default: false
      t.string :status, null: false
      t.timestamps
    end
    add_index :subscriptions, [ :organization_id, :livemode ], unique: true

    create_table :legal_acceptances, id: :uuid do |t|
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :email_hash, null: false
      t.jsonb :versions, null: false, default: {}
      t.string :ip_address
      t.datetime :accepted_at, null: false
    end
    execute <<~SQL
      INSERT INTO legal_acceptances (user_id, email_hash, versions, ip_address, accepted_at)
      SELECT id, encode(digest(lower(email::text), 'sha256'), 'hex'),
        legal_accepted_versions, legal_accepted_ip_address, legal_accepted_at
      FROM users WHERE legal_accepted_at IS NOT NULL
    SQL
  end

  def down
    drop_table :legal_acceptances
    drop_table :subscriptions
  end
end
