require "rails_helper"

RSpec.describe "Постоянный ID магазина", type: :request do
  let(:platform) { PlatformSimulator.new }
  let(:agent) { browser }
  before { connect_platform(platform) }
  after { platform.stop }

  [ true, false ].each do |uninstall_first|
    it "сохраняет identity при смене домена #{uninstall_first ? 'после удаления' : 'без удаления'}" do
      install(agent)
      sign_in(agent, platform)
      store = Shop.first
      generation = store.generation
      if uninstall_first
        agent.get("/uninstall", params: { shop: store.domain, insales_id: 101, token: platform.password })
        expect(agent.response.status).to eq(200)
      end
      platform.rotate("new-domain-token")
      connect_platform(platform, "shop-b.example.test")
      install(agent, domain: "shop-b.example.test", token: "new-domain-token")
      expect(store.reload.domain).to eq("shop-a.example.test")

      sign_in(agent, platform, domain: "shop-b.example.test")

      expect(Shop.count).to eq(1)
      expect(store.reload.domain).to eq("shop-b.example.test")
      expect(store.generation).to be > generation
      expect(store.api_password).to eq(platform.password)
      agent.get("/uninstall", params: { shop: "shop-a.example.test", insales_id: 101, token: platform.password })
      expect(agent.response.status).to eq(403)
      expect(store.reload).to be_active
    end
  end

  it "принимает нового владельца домена и отзывает сессии прежнего" do
    install(agent)
    sign_in(agent, platform)
    old_store = Shop.first
    platform.account_body = { "id" => 202 }
    platform.rotate("new-owner-token")
    other = browser
    install(other, id: 202, token: "new-owner-token")

    sign_in(other, platform, id: 202)

    expect(old_store.reload.domain).to be_nil
    expect(old_store).not_to be_active
    expect(Shop.find_by!(insales_id: 202).domain).to eq("shop-a.example.test")
    agent.get("/")
    expect(agent.response.status).to eq(401)
    expect(AppSession.count).to eq(1)
  end

  it "не меняет домен действующего магазина по поддельной установке" do
    install(agent)
    sign_in(agent, platform)
    connect_platform(platform, "shop-b.example.test")
    install(browser, domain: "shop-b.example.test", token: "fake-token")
    other = browser
    other.get("/login", params: { shop: "shop-b.example.test", insales_id: 101 })
    expect(other.response.status).to eq(401)
    expect(Shop.first.domain).to eq("shop-a.example.test")
    agent.get("/")
    expect(agent.response.status).to eq(200)
  end

  it "не продлевает TTL при повторе установки" do
    install(agent)
    expires_at = InstallationCandidate.first.expires_at
    travel 1.day
    install(agent)
    expect(InstallationCandidate.first.expires_at).to eq(expires_at)
  end

  it "не затрагивает другой магазин при uninstall" do
    install(agent)
    sign_in(agent, platform)
    @other_platform = PlatformSimulator.new(id: 202, token: "install-b")
    other = browser
    install(other, domain: "shop-b.example.test", id: 202, token: "install-b")
    sign_in(other, @other_platform, domain: "shop-b.example.test", id: 202)
    agent.get("/uninstall", params: { shop: "shop-a.example.test", insales_id: 101, token: platform.password })
    expect(agent.response.status).to eq(200)
    other.get("/")
    expect(other.response.status).to eq(200)
    expect(Shop.find_by!(insales_id: 202).api_password).to eq(@other_platform.password)
    expect(AppSession.count).to eq(1)
  ensure
    @other_platform&.stop
  end
end
