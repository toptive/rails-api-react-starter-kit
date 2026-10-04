class CreateTenancy < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations, id: :uuid do |t|
      t.string :name, null: false
      t.citext :slug, null: false
      t.boolean :personal, null: false, default: false
      t.datetime :onboarded_at
      t.timestamps
    end
    add_index :organizations, :slug, unique: true
    add_foreign_key :sessions, :organizations, on_delete: :nullify
    add_reference :users, :last_organization, type: :uuid, foreign_key: { to_table: :organizations, on_delete: :nullify }
    add_column :users, :legal_accepted_at, :datetime
    add_column :users, :legal_accepted_versions, :jsonb, null: false, default: {}
    add_column :users, :legal_accepted_ip_address, :string

    create_table :memberships, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :role, null: false, default: "member"
      t.string :access, null: false, default: "full"
      t.timestamps
    end
    add_index :memberships, [ :organization_id, :user_id ], unique: true
    add_check_constraint :memberships, "role IN ('owner', 'admin', 'member')", name: "memberships_role"
    add_check_constraint :memberships, "access IN ('full', 'viewer')", name: "memberships_access"

    create_table :invitations, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :invited_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.citext :email, null: false
      t.string :role, null: false, default: "member"
      t.string :access, null: false, default: "full"
      t.binary :token_hash, null: false
      t.datetime :accepted_at
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :invitations, :token_hash, unique: true
    add_index :invitations, :expires_at
    add_index :invitations, [ :organization_id, :email ], unique: true,
      where: "accepted_at IS NULL", name: "invitations_pending_email_index"
    add_check_constraint :invitations, "role IN ('admin', 'member')", name: "invitations_role"
    add_check_constraint :invitations, "access IN ('full', 'viewer')", name: "invitations_access"
    add_check_constraint :invitations, "octet_length(token_hash) = 32", name: "invitations_token_hash_length"
  end
end
