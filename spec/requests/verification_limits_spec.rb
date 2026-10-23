require "rails_helper"

RSpec.describe "Лимиты публичных проверок", type: :request do
  let(:platform) { PlatformSimulator.new }
  let(:agent) { browser }
  before { connect_platform(platform) }
  after { platform.stop }

  it "не повторяет проверку одного кандидата в течение десяти секунд" do
    install(agent)
    platform.account_status = 500
    3.times do
      agent.get("/login", params: { shop: "shop-a.example.test", insales_id: 101 })
      expect(agent.response.status).to eq(503)
      expect(agent.response.body).to include("Проверка подключения временно недоступна")
    end
    expect(platform.requests.size).to eq(1)
    travel 11.seconds
    platform.account_status = 200
    sign_in(agent, platform)
    expect(platform.requests.size).to eq(3)
  end

  it "ограничивает суммарную API-квоту при новых поддельных токенах" do
    12.times do |index|
      install(agent, token: "fake-#{index}")
      agent.get("/login", params: { shop: "shop-a.example.test", insales_id: 101 })
    end
    expect(platform.requests.size).to eq(VerificationBudget::LIMIT)
    expect(agent.response.status).to eq(503)
    travel 61.seconds
    install(agent)
    sign_in(agent, platform)
  end

  it "ограничивает частоту callback магазина независимо от IP" do
    31.times do |index|
      agent.get("/install", params: { shop: "shop-a.example.test", insales_id: 101, token: "install-a" },
        headers: { "REMOTE_ADDR" => "192.0.2.#{index + 1}" })
    end
    expect(agent.response.status).to eq(429)
    expect(agent.response.headers["Retry-After"]).to eq("60")
    expect(platform.requests.size).to eq(0)
  end

  it "ограничивает IP при запросах к разным доменам" do
    61.times do |index|
      agent.get("/login", params: { shop: "shop-#{index}.example.test", insales_id: 101 })
    end
    expect(agent.response.status).to eq(429)
    expect(platform.requests.size).to eq(0)
  end
end
