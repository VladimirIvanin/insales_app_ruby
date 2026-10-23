Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.force_ssl = true
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))
  config.log_tags = [ :request_id ]
  config.hosts = [ URI(ENV.fetch("APP_BASE_URL")).host ]
  config.host_authorization = { exclude: ->(request) { request.path == "/healthz" } }
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/healthz" } } }
end
