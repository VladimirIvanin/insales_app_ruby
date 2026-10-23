require "rails_helper"

RSpec.describe "Параметры и журналы callback", type: :request do
  let(:platform) { PlatformSimulator.new }
  let(:agent) { browser }
  before { connect_platform(platform) }
  after { platform.stop }

  %w[token3 user_email user_id email_confirmed].each do |missing|
    it "возвращает 400 при отсутствии #{missing} после начала входа" do
      install(agent)
      callback = begin_login(agent, platform)
      fields = URI.decode_www_form(callback.query).to_h.except(missing)
      agent.get(callback.path, params: fields)
      expect(agent.response.status).to eq(400)
      expect(AppSession.count).to eq(0)
      expect(LoginChallenge.count).to eq(1)
    end
  end

  [ "", nil ].each do |email|
    context "когда email сотрудника равен #{email.inspect}" do
      let(:platform) { PlatformSimulator.new(user_email: email, email_confirmed: "false") }

      it "принимает подписанный callback и открывает страницу подключения" do
        install(agent)
        callback = begin_login(agent, platform)

        agent.get(callback.request_uri)

        expect(agent.response.status).to eq(303)
        expect(AppSession.first.user_id).to eq(42)
        expect(AppSession.first.shop.insales_id).to eq(101)
        expect(LoginChallenge.count).to eq(0)
        agent.follow_redirect!
        expect(agent.response.status).to eq(200)
        expect(agent.response.body).to include("shop-a.example.test")
      end

      it "отклоняет подмену email и позволяет повторить исходный callback" do
        install(agent)
        callback = begin_login(agent, platform)
        fields = URI.decode_www_form(callback.query).to_h.merge("user_email" => "other@example.invalid")

        agent.get(callback.path, params: fields)

        expect(agent.response.status).to eq(403)
        expect(AppSession.count).to eq(0)
        expect(LoginChallenge.count).to eq(1)
        agent.get(callback.request_uri)
        expect(agent.response.status).to eq(303)
      end

      it "отклоняет чужой браузер и повторное использование callback" do
        install(agent)
        callback = begin_login(agent, platform)

        stranger = browser
        stranger.get(callback.request_uri)

        expect(stranger.response.status).to eq(403)
        expect(AppSession.count).to eq(0)
        expect(LoginChallenge.count).to eq(1)
        agent.get(callback.request_uri)
        expect(agent.response.status).to eq(303)
        agent.get(callback.request_uri)
        expect(agent.response.status).to eq(403)
        expect(AppSession.count).to eq(1)
      end
    end
  end

  [ [ "user@example.invalid" ], { "value" => "user@example.invalid" }, "a" * 1025 ].each do |email|
    it "возвращает 400 при некорректном типе или длине email (#{email.class}, #{email.size})" do
      install(agent)
      callback = begin_login(agent, platform)
      fields = URI.decode_www_form(callback.query).to_h.merge("user_email" => email)

      agent.get(callback.path, params: fields)

      expect(agent.response.status).to eq(400)
      expect(AppSession.count).to eq(0)
      expect(LoginChallenge.count).to eq(1)
    end
  end

  it "фильтрует секреты установки, nonce и token3 в настоящем Rails-логе" do
    logfile = Rails.root.join("log/test.log")
    offset = File.size?(logfile) || 0
    token = SecureRandom.hex(24)
    platform.rotate(token)
    install(agent, token: token)
    callback = begin_login(agent, platform)
    nonce = LoginChallenge.first.nonce
    token3 = URI.decode_www_form(callback.query).to_h.fetch("token3")
    agent.get(callback.request_uri)
    expect(agent.response.status).to eq(303)
    logs = File.binread(logfile).byteslice(offset..).force_encoding("UTF-8")
    expect(logs).to include("ConnectionsController", "[FILTERED]")
    expect(logs).not_to include(token, nonce, token3, platform.password, "test-app-secret")
  end
end
