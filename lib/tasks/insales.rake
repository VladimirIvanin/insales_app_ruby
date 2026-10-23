namespace :insales do
  desc "Check configuration, database schema and active shops (read-only API)"
  task doctor: :environment do
    abort "Database migrations are pending" if ActiveRecord::Base.connection_pool.migration_context.needs_migration?
    service = Insales::Lifecycle.new(client_factory: Rails.configuration.x.insales_client_factory)
    failed = false
    Shop.where.not(api_password: nil).find_each do |shop|
      begin
        account = service.client(shop).account
        if account.data.fetch("id") == shop.insales_id
          puts "#{shop.domain}: ok"
        else
          failed = true
          warn "#{shop.domain}: account identity mismatch"
        end
      rescue Insales::ShopNotAllowed
        failed = true
        warn "#{shop.domain}: not allowed"
      rescue Insales::Error => error
        failed = true
        warn "#{shop.domain}: #{error.class.name}"
      end
    end
    abort "Connection checks failed" if failed
    puts "Configuration and database: ok"
  end

  desc "Remove expired sessions, challenges, candidates and old revocations"
  task cleanup: :environment do
    counts = ApplicationRecord.transaction do
      {
        candidates: InstallationCandidate.where("expires_at <= ?", Time.current).delete_all,
        challenges: LoginChallenge.where("expires_at <= ?", Time.current).delete_all,
        sessions: AppSession.where("expires_at <= ? OR last_seen_at <= ?", Time.current, AppSession::IDLE_TIMEOUT.ago).delete_all,
        revocations: RevokedCredential.where("created_at <= ?", RevokedCredential::RETENTION.ago).delete_all,
        permits: VerificationPermit.where("expires_at <= ?", Time.current).delete_all,
        budgets: VerificationBudget.where("window_started_at <= ?", 7.days.ago).delete_all
      }
    end
    puts counts.map { |kind, count| "#{kind}: #{count}" }.join("\n")
  end
end
