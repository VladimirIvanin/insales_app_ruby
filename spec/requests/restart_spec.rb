require "rails_helper"
require "tempfile"
require "open3"

RSpec.describe "Перезапуск процесса", type: :request do
  let(:platform) { PlatformSimulator.new }
  let(:agent) { browser }
  after { platform.stop }

  it "завершает pending-установку после перезапуска до первого входа" do
    connect_platform(platform)
    install(agent)
    expect(Shop.where.not(api_password: nil).count).to eq(0)
    output, error, status = Open3.capture3({ "SIMULATOR_URL" => platform.url }, RbConfig.ruby, "-r", "./config/environment", stdin_data: <<~RUBY)
      factory = ->(domain, password) { Insales::Client.new(shop: domain, password: password, test_url: ENV.fetch("SIMULATOR_URL")) }
      service = Insales::Lifecycle.new(client_factory: factory)
      login = service.begin_login(shop: "shop-a.example.test", insales_id: 101, browser_token: "restarted-browser")
      reply = Net::HTTP.get_response(URI(ENV.fetch("SIMULATOR_URL") + URI(login.redirect_url).request_uri))
      fields = URI.decode_www_form(URI(reply["location"]).query).to_h.symbolize_keys
      grant = service.complete_login(**fields, challenge_id: login.challenge.id, browser_token: "restarted-browser")
      context = service.authenticate(grant.token)
      puts JSON.generate(shop_id: context.shop.insales_id, user_id: context.session.user_id)
    RUBY

    expect(status.success?).to be(true), "#{output}\n#{error}"
    expect(JSON.parse(output)).to eq("shop_id" => 101, "user_id" => 42)
    expect(Shop.first.api_password).to eq(platform.password)
    expect(InstallationCandidate.count).to eq(0)
    expect(AppSession.count).to eq(1)
  end

  it "принимает прежнюю сессию в двух новых Rails-процессах" do
    connect_platform(platform)
    install(agent)
    sign_in(agent, platform)
    cookie = agent.cookies.for(URI("https://app.example.test/"))
    2.times do
      socket = TCPServer.new("127.0.0.1", 0)
      port = socket.addr[1]
      socket.close
      output = Tempfile.new("insales-restart")
      pidfile = Rails.root.join("tmp", "restart-#{port}.pid").to_s
      child = Process.spawn({ "PORT" => port.to_s }, RbConfig.ruby, "bin/rails", "server", "-b", "127.0.0.1", "-p", port.to_s, "-P", pidfile,
        out: output.path, err: output.path)
      Timeout.timeout(15) do
        loop do
          begin
            break if Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/healthz")).code == "200"
          rescue Errno::ECONNREFUSED
            raise "Rails process stopped: #{File.read(output.path)}" unless Process.kill(0, child)
          end
          sleep 0.05
        end
      end
      uri = URI("http://127.0.0.1:#{port}/")
      response = Net::HTTP.start(uri.host, uri.port) do |http|
        http.get("/", "Cookie" => cookie, "Host" => "app.example.test")
      end
      expect(response.code).to eq("200"), "#{response.code}: #{response.body}\n#{File.read(output.path)}"
      expect(response.body).to include("shop-a.example.test")
    ensure
      if child
        Process.kill("TERM", child) rescue Errno::ESRCH
        begin
          Timeout.timeout(5) { Process.wait(child) }
        rescue Timeout::Error
          Process.kill("KILL", child)
          Process.wait(child)
        end
      end
      output&.close!
      FileUtils.rm_f(pidfile) if pidfile
    end
  end
end
