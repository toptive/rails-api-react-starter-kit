class CreateTranslationFills < ActiveRecord::Migration[8.1]
  def change
    change_column :translations, :key, :string, limit: 255
    create_table :translation_fills, id: :uuid do |t|
      t.references :session, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :locale, null: false
      t.string :ip_address
      t.integer :count
      t.string :error_code
      t.datetime :completed_at
      t.timestamps
    end
  end
end
