require "rails_helper"
require "open3"
require "tmpdir"

RSpec.describe "Обновление схемы" do
  it "переносит active, pending и revocations со старой схемы без потери credentials" do
    Dir.mktmpdir("migration") do |directory|
      output, error, status = Open3.capture3({ "TEST_DB" => File.join(directory, "legacy.sqlite3") },
        RbConfig.ruby, "-r", "./config/environment", stdin_data: <<~'RUBY')
        ActiveRecord::Migration.verbose = false
        context = ActiveRecord::Base.connection_pool.migration_context
        context.migrate(20261023000000)
        store = Shop.create!(insales_id: 101, domain: "shop-a.example.test", generation: 4,
          api_password: "legacy-password", credential_digest: "legacy-digest")
        InstallationCandidate.create!(shop_id: store.id, insales_id: 101,
          api_password: "pending-password", credential_digest: "pending-digest", expires_at: 1.day.from_now)
        RevokedCredential.create!(shop_id: store.id, insales_id: 101, credential_digest: "old-digest")
        obsolete = InstallationCandidate.create!(id: 8, shop_id: store.id, insales_id: 101,
          api_password: "obsolete-password", credential_digest: "obsolete-digest", expires_at: 1.day.from_now)
        obsolete.destroy!
        original_sequence = ActiveRecord::Base.connection.select_value("SELECT seq FROM sqlite_sequence WHERE name = 'installation_candidates'")
        Shop.create!(domain: "shop-b.example.test")
        context.migrate
        [ Shop, InstallationCandidate, RevokedCredential ].each(&:reset_column_information)
        raise "active lost" unless Shop.first.api_password == "legacy-password" && Shop.first.generation == 4
        candidate = InstallationCandidate.first
        raise "pending lost" unless candidate.domain == "shop-a.example.test" && candidate.api_password == "pending-password"
        revoked = RevokedCredential.first
        raise "revocation lost" unless revoked.domain == "shop-a.example.test" && revoked.created_at
        raise "anonymous shop retained" unless Shop.count == 1
        Insales::Lifecycle.new.install(shop: "shop-a.example.test", insales_id: 101, token: "fresh-token")
        fresh = InstallationCandidate.order(:id).last
        raise "generation sequence regressed: was #{original_sequence}, allocated #{fresh.id}" unless fresh.id > 8
        raise "legacy indexes retained" if ActiveRecord::Base.connection.indexes(:installation_candidates).any? { |index| index.columns == ["credential_digest"] }
        puts "migration: ok"
      RUBY
      expect(status.success?).to be(true), "#{output}\n#{error}"
      expect(output).to include("migration: ok")
    end
  end
end
