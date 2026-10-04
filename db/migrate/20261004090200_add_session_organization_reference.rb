class AddSessionOrganizationReference < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :organization_id, :uuid
    add_index :sessions, :organization_id
  end
end
