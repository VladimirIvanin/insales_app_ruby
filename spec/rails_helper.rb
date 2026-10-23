require_relative "support/test_environment"
require_relative "../config/environment"
require "rspec/rails"
require "fileutils"
FileUtils.mkdir_p(Rails.root.join("tmp"))
ActiveRecord::Migration.verbose = false
ActiveRecord::Base.connection_pool.migration_context.migrate
require_relative "support/platform_simulator"
require_relative "support/browser_flow"

RSpec.configure do |config|
  config.use_transactional_fixtures = false
  config.include ActiveSupport::Testing::TimeHelpers
  config.include BrowserFlow
  config.before do
    ConnectionsController::RATE_LIMIT_STORE.clear
    @previous_client_factory = Rails.configuration.x.insales_client_factory
    [ VerificationPermit, VerificationBudget, AppSession, LoginChallenge, InstallationCandidate, RevokedCredential, Shop ].each(&:delete_all)
  end
  config.after do
    travel_back
    Rails.configuration.x.insales_client_factory = @previous_client_factory
  end
  config.after(:suite) do
    ActiveRecord::Base.connection_handler.clear_all_connections!
    [ "", "-wal", "-shm" ].each { |suffix| FileUtils.rm_f(ENV.fetch("TEST_DB") + suffix) }
  end
end
