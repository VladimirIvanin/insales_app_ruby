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
