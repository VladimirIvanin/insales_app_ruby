ENV["RAILS_ENV"] = "test"
ENV["TEST_DB"] = File.expand_path("../../tmp/rspec-#{Process.pid}.sqlite3", __dir__)
{
  "INSALES_APP_ID" => "test-app", "INSALES_APP_SECRET" => "test-app-secret",
  "APP_BASE_URL" => "https://app.example.test", "ALLOWED_SHOPS" => "shop-a.example.test,shop-b.example.test",
  "AR_ENCRYPTION_PRIMARY_KEY" => "test-encryption-key-" * 3,
  "AR_ENCRYPTION_KEY_DERIVATION_SALT" => "test-encryption-salt-" * 3,
  "SECRET_KEY_BASE" => "test-cookie-key-" * 8
}.each { |name, value| ENV[name] = value }
