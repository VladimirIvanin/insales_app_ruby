require "rails_helper"

RSpec.describe "Политика доступа", type: :request do
  let(:platform) { PlatformSimulator.new }
  let(:agent) { browser }
  before { connect_platform(platform) }
  after { platform.stop }

  it "отзывает сессии и challenges магазина, удалённого из allowlist" do
    install(agent)
    sign_in(agent, platform)
    begin_login(agent, platform)
    allow(Rails.configuration.x.insales).to receive(:allowed_shops).and_return([ "shop-b.example.test" ])
    agent.get("/")
    expect(agent.response.status).to eq(401)
    expect(AppSession.count).to eq(0)
    expect(LoginChallenge.count).to eq(0)
    expect { Insales::Lifecycle.new.client(Shop.first) }.to raise_error(Insales::ShopNotAllowed)
  end

  it "допускает повтор logout с уже истёкшей сессией" do
    install(agent)
    sign_in(agent, platform)
    travel 2.hours
    agent.post("/logout")
    expect(agent.response.status).to eq(200)
    expect(agent.response.body).to include("Вы вышли")
    expect(AppSession.where("expires_at > ?", Time.current).count).to eq(0)
    agent.post("/logout")
    expect(agent.response.status).to eq(200)
  end

  it "показывает ограничение одного магазина на профиль браузера" do
    install(agent)
    sign_in(agent, platform)
    expect(agent.response.body).to include("переключит все вкладки", "отдельные профили браузера")
  end

  it "не повторяет API-запрос при обновлении результата и прямом GET" do
    install(agent)
    sign_in(agent, platform)
    platform.requests.clear
    agent.get("/account")
    expect(agent.response.status).to eq(302)
    expect(platform.requests.size).to eq(0)
    agent.post("/probe")
    expect(agent.response.status).to eq(303)
    agent.follow_redirect!
    expect(agent.response.status).to eq(200)
    expect(platform.requests.size).to eq(1)
    agent.get("/account")
    expect(agent.response.status).to eq(302)
    expect(platform.requests.size).to eq(1)
  end
end
