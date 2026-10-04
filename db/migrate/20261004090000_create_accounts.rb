class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto"
    enable_extension "citext"

    create_table :users, id: :uuid do |t|
      t.string :name, null: false, default: ""
      t.citext :email, null: false
      t.string :hashed_password
      t.datetime :confirmed_at
      t.string :locale, null: false, default: "en"
      t.string :role, null: false, default: "user"
      t.boolean :optional_emails, null: false, default: true
      t.timestamps
    end
    add_index :users, :email, unique: true
    add_check_constraint :users, "role IN ('user', 'superadmin')", name: "users_role"

    create_table :sessions, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.binary :token_hash, null: false
      t.datetime :expires_at, null: false
      t.datetime :authenticated_at, null: false
      t.datetime :sudo_until
      t.references :impersonator_user, type: :uuid, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :impersonator_session, type: :uuid, foreign_key: { to_table: :sessions, on_delete: :cascade }
      t.datetime :revoked_at
      t.string :ip_address
      t.string :user_agent, limit: 255
      t.datetime :last_used_at
      t.datetime :renewed_at
      t.timestamps
    end
    add_index :sessions, :token_hash, unique: true
    add_index :sessions, :expires_at
    add_check_constraint :sessions, "octet_length(token_hash) = 32", name: "sessions_token_hash_length"
    add_check_constraint :sessions, "impersonator_user_id IS NULL OR sudo_until IS NULL", name: "sessions_impersonation_no_sudo"

    create_table :user_tokens, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.binary :token_hash, null: false
      t.string :context, null: false
      t.citext :sent_to, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
    end
    add_index :user_tokens, [ :token_hash, :context ], unique: true
    add_check_constraint :user_tokens, "octet_length(token_hash) = 32", name: "user_tokens_hash_length"

    create_table :impersonations, id: :uuid do |t|
      t.references :admin, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :target_user, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :reason, null: false
      t.datetime :ended_at
      t.timestamps
    end
    add_reference :sessions, :impersonation, type: :uuid, foreign_key: true

    create_table :audit_events, id: :uuid do |t|
      t.string :action, null: false
      t.uuid :actor_id
      t.uuid :impersonator_id
      t.uuid :organization_id
      t.string :subject_type
      t.uuid :subject_id
      t.jsonb :metadata, null: false, default: {}
      t.string :ip_address
      t.datetime :created_at, null: false
    end
    add_index :audit_events, :actor_id
    add_index :audit_events, :organization_id
    add_index :audit_events, [ :subject_type, :subject_id ]
    add_index :audit_events, :created_at
  end
end
