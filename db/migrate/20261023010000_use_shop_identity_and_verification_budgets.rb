class UseShopIdentityAndVerificationBudgets < ActiveRecord::Migration[8.1]
  def up
    candidate_sequence = select_value("SELECT seq FROM sqlite_sequence WHERE name = 'installation_candidates'").to_i
    add_column :installation_candidates, :domain, :string
    execute "UPDATE installation_candidates SET domain = (SELECT domain FROM shops WHERE shops.id = installation_candidates.shop_id)"
    change_column_null :installation_candidates, :domain, false
    remove_foreign_key :installation_candidates, :shops
    remove_index :installation_candidates, name: "index_installation_candidates_on_shop_id_and_credential_digest"
    remove_column :installation_candidates, :shop_id
    add_index :installation_candidates, [ :insales_id, :domain, :credential_digest ], unique: true, name: "index_candidates_on_identity_and_credential"
    add_index :installation_candidates, :domain
    add_column :installation_candidates, :last_checked_at, :datetime
    add_column :installation_candidates, :verification_status, :string

    add_column :revoked_credentials, :domain, :string
    add_column :revoked_credentials, :created_at, :datetime
    execute "UPDATE revoked_credentials SET domain = (SELECT domain FROM shops WHERE shops.id = revoked_credentials.shop_id), created_at = CURRENT_TIMESTAMP"
    change_column_null :revoked_credentials, :domain, false
    change_column_null :revoked_credentials, :created_at, false
    remove_foreign_key :revoked_credentials, :shops
    remove_index :revoked_credentials, name: "index_revoked_credentials_identity"
    remove_column :revoked_credentials, :shop_id
    add_index :revoked_credentials, [ :insales_id, :domain, :credential_digest ], unique: true, name: "index_revoked_credentials_identity"

    execute "DELETE FROM shops WHERE insales_id IS NULL"
    change_column_null :shops, :insales_id, false
    change_column_null :shops, :domain, true

    create_table :verification_budgets do |t|
      t.string :domain, null: false
      t.datetime :window_started_at, null: false
      t.integer :attempts, default: 0, null: false
    end
    add_index :verification_budgets, :domain, unique: true

    create_table :verification_permits do |t|
      t.datetime :expires_at, null: false
    end
    create_table :installation_sequences do |t|
      t.bigint :last_value, default: 0, null: false
    end
    sequence = [ candidate_sequence, select_value("SELECT MAX(id) FROM installation_candidates").to_i,
      select_value("SELECT MAX(generation) FROM shops").to_i ].max
    execute "INSERT INTO installation_sequences (id, last_value) VALUES (1, #{sequence})"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Candidates and revocations now belong to a stable shop identity"
  end
end
