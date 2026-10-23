Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = %w[localhost 127.0.0.1].include?(URI(ENV.fetch("APP_BASE_URL", "http://127.0.0.1:8765")).host)
  config.active_record.migration_error = :page_load
  config.hosts << URI(ENV.fetch("APP_BASE_URL", "http://127.0.0.1:8765")).host
end
