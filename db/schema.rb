# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_23_010000) do
  create_table "app_sessions", force: :cascade do |t|
    t.integer "shop_id", null: false
    t.bigint "generation", null: false
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_app_sessions_on_shop_id"
    t.index ["token_digest"], name: "index_app_sessions_on_token_digest", unique: true
  end

  create_table "installation_candidates", force: :cascade do |t|
    t.bigint "insales_id", null: false
    t.text "api_password", null: false
    t.string "credential_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "domain", null: false
    t.datetime "last_checked_at"
    t.string "verification_status"
    t.index ["domain"], name: "index_installation_candidates_on_domain"
    t.index ["insales_id", "domain", "credential_digest"], name: "index_candidates_on_identity_and_credential", unique: true
  end

  create_table "installation_sequences", force: :cascade do |t|
    t.bigint "last_value", default: 0, null: false
  end

  create_table "login_challenges", force: :cascade do |t|
    t.integer "shop_id", null: false
    t.bigint "generation", null: false
    t.string "nonce", null: false
    t.string "browser_digest", null: false
    t.datetime "expires_at", null: false
    t.index ["shop_id"], name: "index_login_challenges_on_shop_id"
  end

  create_table "revoked_credentials", force: :cascade do |t|
    t.bigint "insales_id", null: false
    t.string "credential_digest", null: false
    t.string "domain", null: false
    t.datetime "created_at", null: false
    t.index ["insales_id", "domain", "credential_digest"], name: "index_revoked_credentials_identity", unique: true
  end

  create_table "shops", force: :cascade do |t|
    t.string "domain"
    t.bigint "insales_id", null: false
    t.bigint "generation", default: 0, null: false
    t.text "api_password"
    t.string "credential_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_shops_on_domain", unique: true
    t.index ["insales_id"], name: "index_shops_on_insales_id", unique: true
  end

  create_table "verification_budgets", force: :cascade do |t|
    t.string "domain", null: false
    t.datetime "window_started_at", null: false
    t.integer "attempts", default: 0, null: false
    t.index ["domain"], name: "index_verification_budgets_on_domain", unique: true
  end

  create_table "verification_permits", force: :cascade do |t|
    t.datetime "expires_at", null: false
  end

  add_foreign_key "app_sessions", "shops"
  add_foreign_key "login_challenges", "shops"
end
