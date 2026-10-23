require "rails_helper"

RSpec.describe "Независимые входы вкладок", type: :request do
  let(:platform) { PlatformSimulator.new }
  let(:agent) { browser }

  before do
    @other_platform = PlatformSimulator.new(id: 202, token: "install-b")
    connect_platform(platform)
  end
  after do
    platform.stop
    @other_platform.stop
  end

  it "завершает оба входа и явно отклоняет действие старой вкладки" do
    install(agent)
    install(agent, domain: "shop-b.example.test", id: 202, token: "install-b")
    first = begin_login(agent, platform)
    second = begin_login(agent, @other_platform, domain: "shop-b.example.test", id: 202)
    agent.get(first.request_uri)
    expect(agent.response.status).to eq(303)
    old_tab = URI(agent.response.location).request_uri
    agent.get(second.request_uri)
    expect(agent.response.status).to eq(303)
    agent.get(URI(agent.response.location).request_uri)
    expect(agent.response.status).to eq(200)
    expect(agent.response.body).to include("shop-b.example.test")
    agent.get(old_tab)
    expect(agent.response.status).to eq(409)
    expect(agent.response.body).to include("Другая вкладка сменила магазин")
  end

  it "соблюдает Retry-After дольше обычного cooldown кандидата" do
    install(agent)
    platform.account_status = 429
    platform.retry_after = "60"
    agent.get("/login", params: { shop: "shop-a.example.test", insales_id: 101 })
    expect(agent.response.status).to eq(503)
    expect(platform.requests.size).to eq(1)
    travel 11.seconds
    agent.get("/login", params: { shop: "shop-a.example.test", insales_id: 101 })
    expect(agent.response.status).to eq(503)
    expect(platform.requests.size).to eq(1)
    travel 50.seconds
    platform.account_status = 200
    sign_in(agent, platform)
    expect(platform.requests.size).to eq(3)
  end
end
