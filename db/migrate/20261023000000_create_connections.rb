class CreateConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :shops do |t|
      t.string :domain, null: false
      t.bigint :insales_id
      t.bigint :generation, null: false, default: 0
      t.text :api_password
      t.string :credential_digest
      t.timestamps
    end
    add_index :shops, :domain, unique: true
    add_index :shops, :insales_id, unique: true

    create_table :installation_candidates do |t|
      t.references :shop, null: false, foreign_key: true
      t.bigint :insales_id, null: false
      t.text :api_password, null: false
      t.string :credential_digest, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :installation_candidates, [ :shop_id, :credential_digest ], unique: true

    create_table :login_challenges do |t|
      t.references :shop, null: false, foreign_key: true
      t.bigint :generation, null: false
      t.string :nonce, null: false
      t.string :browser_digest, null: false
      t.datetime :expires_at, null: false
    end

    create_table :app_sessions do |t|
      t.references :shop, null: false, foreign_key: true
      t.bigint :generation, null: false
      t.bigint :user_id, null: false
      t.string :token_digest, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :app_sessions, :token_digest, unique: true

    create_table :revoked_credentials do |t|
      t.references :shop, null: false, foreign_key: true
      t.bigint :insales_id, null: false
      t.string :credential_digest, null: false
    end
    add_index :revoked_credentials, [ :shop_id, :insales_id, :credential_digest ], unique: true, name: "index_revoked_credentials_identity"
  end
end
