require "rails_helper"

RSpec.describe "Защита форм", type: :request do
  let(:platform) { PlatformSimulator.new }
  let(:agent) { browser }
  around do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
  before do
    connect_platform(platform)
    install(agent)
    sign_in(agent, platform)
  end
  after { platform.stop }

  it "допускает POST с токеном формы и своим Origin" do
    token = csrf(agent)
    expect(token).to be_present
    agent.post("/probe", params: { authenticity_token: token }, headers: { "Origin" => "https://app.example.test" })
    expect(agent.response.status).to eq(303)
    agent.follow_redirect!
    expect(agent.response.status).to eq(200)
  end

  it "отклоняет отсутствие и подмену токена" do
    agent.post("/logout")
    expect(agent.response.status).to eq(422)
    agent.post("/logout", params: { authenticity_token: "invalid" })
    expect(agent.response.status).to eq(422)
    expect(AppSession.count).to eq(1)
  end

  it "отклоняет чужой и null Origin даже с правильным токеном" do
    token = csrf(agent)
    [ "https://evil.example.test", "null" ].each do |origin|
      agent.post("/logout", params: { authenticity_token: token }, headers: { "Origin" => origin })
      expect(agent.response.status).to eq(422)
    end
    expect(AppSession.count).to eq(1)
  end

  it "выдаёт защищённую cookie" do
    begin_login(agent, platform)
    header = agent.response.headers.fetch("set-cookie")
    expect(header.to_s).to match(/httponly/i)
    expect(header.to_s).to match(/secure/i)
    expect(header.to_s).to match(/samesite=lax/i)
    expect(header.to_s).not_to match(/domain=/i)
  end

  it "меняет ID сессии и удаляет прежнее состояние после token3" do
    callback = begin_login(agent, platform)
    previous_id = agent.request.session.id.public_id
    expect(agent.request.session.to_hash).to include("browser_token", "challenge_id")

    agent.get(callback.request_uri)

    expect(agent.response.status).to eq(303)
    expect(agent.request.session.id.public_id).not_to eq(previous_id)
    expect(agent.request.session.to_hash).not_to include("browser_token", "challenge_id")
    expect(agent.request.session[:auth_token]).to be_present
    agent.get("/")
    expect(agent.response.status).to eq(200)
    expect(AppSession.count).to eq(1)
  end
end
