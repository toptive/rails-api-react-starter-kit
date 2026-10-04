class CreateAdminResources < ActiveRecord::Migration[8.1]
  def change
    create_table :translations, id: :uuid do |t|
      t.string :key, null: false
      t.string :locale, null: false
      t.text :value, null: false, default: ""
      t.boolean :edited, null: false, default: false
      t.timestamps
    end
    add_index :translations, [ :key, :locale ], unique: true

    create_table :legal_documents, id: :uuid do |t|
      t.string :slug, null: false
      t.uuid :published_version_id
      t.timestamps
    end
    add_index :legal_documents, :slug, unique: true
    create_table :legal_document_versions, id: :uuid do |t|
      t.references :legal_document, type: :uuid, null: false, foreign_key: true
      t.integer :number, null: false
      t.jsonb :titles, null: false, default: {}
      t.jsonb :bodies, null: false, default: {}
      t.string :note, limit: 255
      t.datetime :published_at
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :legal_document_versions, [ :legal_document_id, :number ], unique: true
    add_foreign_key :legal_documents, :legal_document_versions, column: :published_version_id
    add_reference :legal_acceptances, :legal_document_version, type: :uuid, foreign_key: true
    add_index :legal_acceptances, [ :user_id, :legal_document_version_id ], unique: true
    add_index :audit_events, :subject_id

    create_table :jobs_tickets, id: :uuid do |t|
      t.references :session, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :jobs_tickets, :expires_at
  end
end
