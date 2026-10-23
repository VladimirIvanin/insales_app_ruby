require_relative "boot"
require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
Bundler.require(*Rails.groups)
require_relative "../lib/insales/protocol"
require_relative "../lib/insales/settings"

module InsalesAppRuby
  class Application < Rails::Application
    config.load_defaults 8.1
    config.i18n.default_locale = :ru
    config.time_zone = "UTC"
    config.autoload_lib(ignore: %w[tasks insales/protocol.rb insales/settings.rb])
    config.generators.system_tests = nil
    config.active_support.deprecation = :log
    config.action_dispatch.rescue_responses["ActionController::InvalidAuthenticityToken"] = :unprocessable_content
  end
end
