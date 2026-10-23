require "rails_helper"
require "open3"
require "tmpdir"

RSpec.describe "Production-конфигурация" do
  it "допускает health по IP без forwarded-заголовков и защищает обычные пути" do
    Dir.mktmpdir("production-health") do |directory|
      output, error, status = Open3.capture3({ "RAILS_ENV" => "production", "APP_DB" => File.join(directory, "app.sqlite3") },
        RbConfig.ruby, "-r", "./config/environment", stdin_data: <<~'RUBY')
        browser = ActionDispatch::Integration::Session.new(Rails.application)
        browser.host! "127.0.0.1"
        browser.get("/healthz")
        raise "health: #{browser.response.status}" unless browser.response.status == 200
        browser.get("/")
        raise "host: #{browser.response.status}" unless browser.response.status == 403
        browser.host! "app.example.test"
        browser.get("/")
        raise "ssl: #{browser.response.status}" unless browser.response.status == 301
        puts "production health: ok"
      RUBY
      expect(status.success?).to be(true), "#{output}\n#{error}"
      expect(output).to include("production health: ok")
    end
  end
end
