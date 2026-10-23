require "rails_helper"

RSpec.describe "Жизненный цикл приложения", type: :request do
  let(:platform) { PlatformSimulator.new }
  let(:agent) { browser }
  before { connect_platform(platform) }
  after { platform.stop }

  it "сохраняет кандидата без запроса API и без сессии" do
    install(agent)
    expect(platform.requests.size).to eq(0)
    expect(InstallationCandidate.count).to eq(1)
    expect(Shop.where.not(api_password: nil).count).to eq(0)
    agent.get("/")
    expect(agent.response.status).to eq(401)
    expect(AppSession.count).to eq(0)
  end

  it "проходит install, token3, probe, повторный вход и uninstall" do
    install(agent)
    sign_in(agent, platform)
    expect(Shop.first.insales_id).to eq(101)
    expect(AppSession.first.user_id).to eq(42)
    expect(agent.response.headers["Cache-Control"]).to eq("no-store")
    expect(agent.response.headers["Referrer-Policy"]).to eq("same-origin")
    agent.post("/probe")
    expect(agent.response.status).to eq(303)
    agent.follow_redirect!
    expect(agent.response.status).to eq(200)
    expect(agent.response.body).to include("Тестовый магазин", "1/300")
    platform.requests.clear
    sign_in(agent, platform)
    expect(platform.requests.size).to eq(1)
    agent.get("/uninstall", params: { shop: "shop-a.example.test", insales_id: 101, token: platform.password })
    expect(agent.response.status).to eq(200)
    expect(Shop.where.not(api_password: nil).count).to eq(0)
    expect(AppSession.count).to eq(0)
    expect(agent.response.headers["Referrer-Policy"]).to eq("no-referrer")
    agent.get("/")
    expect(agent.response.status).to eq(401)
  end

  it "сохраняет cookie и credentials после переподключения к SQLite" do
    install(agent)
    sign_in(agent, platform)
    ActiveRecord::Base.connection_handler.clear_all_connections!
    agent.get("/")
    expect(agent.response.status).to eq(200)
    expect(Shop.first.api_password).to eq(platform.password)
  end

  it "не создаёт дубли установки и не отзывает действующую сессию" do
    install(agent)
    install(agent)
    expect(InstallationCandidate.count).to eq(1)
    sign_in(agent, platform)
    generation = Shop.first.generation
    install(agent)
    expect(Shop.first.generation).to eq(generation)
    expect(InstallationCandidate.count).to eq(0)
    agent.get("/")
    expect(agent.response.status).to eq(200)
  end

  it "не создаёт сессию по параметрам первоначального login" do
    install(agent)
    begin_login(agent, platform)
    expect(AppSession.count).to eq(0)
    agent.get("/")
    expect(agent.response.status).to eq(401)
  end

  it "отклоняет повтор token3 и callback из другого браузера" do
    install(agent)
    callback = begin_login(agent, platform)
    stranger = browser
    stranger.get(callback.request_uri)
    expect(stranger.response.status).to eq(403)
    expect(AppSession.count).to eq(0)
    agent.get(callback.request_uri)
    expect(agent.response.status).to eq(303)
    agent.get(callback.request_uri)
    expect(agent.response.status).to eq(403)
    expect(AppSession.count).to eq(1)
  end

  it "отклоняет подмену подписанного пользователя" do
    install(agent)
    callback = begin_login(agent, platform)
    parameters = URI.decode_www_form(callback.query).to_h.merge("user_id" => "99")
    agent.get(callback.path, params: parameters)
    expect(agent.response.status).to eq(403)
    expect(AppSession.count).to eq(0)
  end

  it "отклоняет просроченный challenge" do
    install(agent)
    callback = begin_login(agent, platform)
    travel 6.minutes
    agent.get(callback.request_uri)
    expect(agent.response.status).to eq(403)
  end

  it "отзывает сессию при logout, включая повтор старой cookie" do
    install(agent)
    sign_in(agent, platform)
    saved_cookie = agent.cookies.for(URI("https://app.example.test/"))
    agent.post("/logout")
    expect(agent.response.status).to eq(200)
    expect(AppSession.count).to eq(0)
    replay = browser
    replay.get("/", headers: { "Cookie" => saved_cookie })
    expect(replay.response.status).to eq(401)
  end

  it "отклоняет изменённую cookie" do
    install(agent)
    sign_in(agent, platform)
    stranger = browser
    stranger.get("/", headers: { "Cookie" => "__Host-insales_session=invalid" })
    expect(stranger.response.status).to eq(401)
  end

  it "проверяет срок бездействия на сервере" do
    install(agent)
    sign_in(agent, platform)
    travel 31.minutes
    agent.get("/")
    expect(agent.response.status).to eq(401)
    expect(AppSession.count).to eq(0)
  end

  it "проверяет абсолютный срок независимо от активности" do
    install(agent)
    sign_in(agent, platform)
    2.times do
      travel 20.minutes
      agent.get("/")
      expect(agent.response.status).to eq(200)
    end
    travel 21.minutes
    agent.get("/")
    expect(agent.response.status).to eq(401)
  end

  [ 302, 404, 429, 500 ].each do |status|
    it "сохраняет кандидата при API #{status} и допускает повторный вход" do
      install(agent)
      platform.account_status = status
      agent.get("/login", params: { shop: "shop-a.example.test", insales_id: 101 })
      expect(agent.response.status).to eq(503)
      expect(InstallationCandidate.count).to eq(1)
      expect(Shop.where.not(api_password: nil).count).to eq(0)
      platform.account_status = 200
      travel 11.seconds
      sign_in(agent, platform)
      expect(InstallationCandidate.count).to eq(0)
      expect(AppSession.first.user_id).to eq(42)
    end
  end

  it "сохраняет кандидата при отказе транспорта" do
    install(agent)
    platform.stop
    agent.get("/login", params: { shop: "shop-a.example.test", insales_id: 101 })
    expect(agent.response.status).to eq(503)
    expect(InstallationCandidate.count).to eq(1)
  end

  it "не принимает чужой account.id и неверные credentials" do
    install(agent)
    platform.account_body = { "id" => 202 }
    agent.get("/login", params: { shop: "shop-a.example.test", insales_id: 101 })
    expect(agent.response.status).to eq(401)
    expect(InstallationCandidate.count).to eq(0)
    install(agent, token: "wrong-token")
    agent.get("/login", params: { shop: "shop-a.example.test", insales_id: 101 })
    expect(agent.response.status).to eq(401)
    expect(InstallationCandidate.count).to eq(0)
  end

  it "сохраняет кандидата при некорректном ответе API" do
    install(agent)
    platform.account_body = []
    agent.get("/login", params: { shop: "shop-a.example.test", insales_id: 101 })
    expect(agent.response.status).to eq(503)
    expect(InstallationCandidate.count).to eq(1)
  end

  it "сохраняет действующий вход при временной ошибке новой установки" do
    install(agent)
    sign_in(agent, platform)
    generation = Shop.first.generation
    install(agent, token: "next-token")
    platform.account_status = 500
    sign_in(agent, platform)
    expect(Shop.first.generation).to eq(generation)
    expect(InstallationCandidate.count).to eq(1)
  end

  it "освобождает место после истечения срока без API-запросов" do
    5.times { |index| install(agent, token: "token-#{index}") }
    expect(InstallationCandidate.count).to eq(5)
    travel 8.days
    install(agent, token: "fresh")
    expect(InstallationCandidate.count).to eq(1)
    expect(platform.requests.size).to eq(0)
  end

  it "принимает настоящую установку после заполнения очереди чужими identity" do
    5.times { |index| install(agent, token: "fake-#{index}", id: 999) }

    install(agent)

    expect(InstallationCandidate.count).to eq(5)
    expect(platform.requests.size).to eq(1)
    expect(Shop.where.not(api_password: nil).count).to eq(0)
    expect(AppSession.count).to eq(0)
    sign_in(agent, platform)
    expect(Shop.first.api_password).to eq(platform.password)
    expect(Shop.first.insales_id).to eq(101)
    expect(AppSession.first.user_id).to eq(42)
  end

  it "сохраняет настоящего старейшего кандидата при переполнении" do
    install(agent)
    genuine = InstallationCandidate.first
    4.times { |index| install(agent, token: "fake-#{index}", id: 999) }

    install(agent, token: "overflow", id: 999)

    expect(InstallationCandidate.count).to eq(5)
    expect(InstallationCandidate.exists?(genuine.id)).to be(true)
    expect(platform.requests.size).to eq(2)
    expect(Shop.where.not(api_password: nil).count).to eq(0)
    sign_in(agent, platform)
    expect(Shop.first.api_password).to eq(platform.password)
  end

  [ 429, 500 ].each do |status|
    it "не вытесняет кандидатов при переполнении и API #{status}, затем восстанавливает установку" do
      5.times { |index| install(agent, token: "fake-#{index}", id: 999) }
      previous_ids = InstallationCandidate.ids
      platform.account_status = status

      agent.get("/install", params: { shop: "shop-a.example.test", insales_id: 101, token: "install-a" })

      expect(agent.response.status).to eq(503)
      expect(InstallationCandidate.ids).to eq(previous_ids)
      expect(platform.requests.size).to eq(1)
      platform.account_status = 200
      travel 11.seconds
      install(agent)
      sign_in(agent, platform)
      expect(AppSession.first.user_id).to eq(42)
    end
  end

  it "проверяет account.id перед освобождением места в очереди" do
    install(agent, id: 999)
    4.times { |index| install(agent, token: "fake-#{index}", id: 999) }

    install(agent, token: "next-token")

    expect(InstallationCandidate.where(insales_id: 101).count).to eq(1)
    expect(platform.requests.size).to eq(1)
    platform.rotate("next-token")
    sign_in(agent, platform)
    expect(Shop.first.insales_id).to eq(101)
  end

  it "сохраняет очередь и действующую сессию при отказе транспорта во время admission" do
    install(agent)
    sign_in(agent, platform)
    5.times { |index| install(agent, token: "fake-#{index}", id: 999) }
    previous_ids = InstallationCandidate.ids
    generation = Shop.first.generation
    platform.stop

    agent.get("/install", params: { shop: "shop-a.example.test", insales_id: 101, token: "next-token" })

    expect(agent.response.status).to eq(503)
    expect(InstallationCandidate.ids).to eq(previous_ids)
    expect(Shop.first.generation).to eq(generation)
    agent.get("/")
    expect(agent.response.status).to eq(200)
  end

  it "ограничивает проверку переполненной очереди и сохраняет медленного настоящего кандидата" do
    install(agent)
    4.times { |index| install(agent, token: "fake-#{index}", id: 999) }
    previous_ids = InstallationCandidate.ids
    stub_const("Insales::Lifecycle::ADMISSION_TIMEOUT", 0.05)
    platform.delay = 0.3
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    agent.get("/install", params: { shop: "shop-a.example.test", insales_id: 999, token: "overflow" })

    expect(agent.response.status).to eq(503)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.25
    expect(InstallationCandidate.ids).to eq(previous_ids)
    expect(platform.requests.size).to eq(1)
    platform.delay = 0
    travel 11.seconds
    sign_in(agent, platform)
  end

  it "не удаляет active при uninstall другого кандидата" do
    install(agent)
    sign_in(agent, platform)
    install(agent, token: "pending-token")
    pending_password = Digest::MD5.hexdigest("pending-token" + "test-app-secret")
    agent.get("/uninstall", params: { shop: "shop-a.example.test", insales_id: 101, token: pending_password })
    expect(agent.response.status).to eq(200)
    expect(Shop.first).to be_active
    expect(InstallationCandidate.count).to eq(0)
    agent.get("/")
    expect(agent.response.status).to eq(200)
  end

  it "сохраняет новую pending при удалении active и подтверждает повтор удаления" do
    install(agent)
    sign_in(agent, platform)
    password = platform.password
    install(agent, token: "next-token")
    2.times do
      agent.get("/uninstall", params: { shop: "shop-a.example.test", insales_id: 101, token: password })
      expect(agent.response.status).to eq(200)
    end
    expect(InstallationCandidate.count).to eq(1)
    expect(Shop.where.not(api_password: nil).count).to eq(0)
    platform.rotate("next-token")
    sign_in(agent, platform)
    agent.get("/uninstall", params: { shop: "shop-a.example.test", insales_id: 101, token: password })
    expect(agent.response.status).to eq(200)
    expect(Shop.first.api_password).to eq(platform.password)
  end

  it "отклоняет неверный uninstall и сохраняет состояние" do
    install(agent)
    sign_in(agent, platform)
    agent.get("/uninstall", params: { shop: "shop-a.example.test", insales_id: 101, token: "0" * 32 })
    expect(agent.response.status).to eq(403)
    expect(Shop.first).to be_active
    expect(AppSession.count).to eq(1)
  end

  it "не переносит сессию на новое поколение подключения" do
    install(agent)
    callback = begin_login(agent, platform)
    other = browser
    install(other, token: "next-token")
    platform.rotate("next-token")
    sign_in(other, platform)
    agent.get(callback.request_uri)
    expect(agent.response.status).to eq(403)
    expect(AppSession.count).to eq(1)
  end

  it "отзывает старую сессию при переустановке" do
    install(agent)
    sign_in(agent, platform)
    other = browser
    install(other, token: "next-token")
    platform.rotate("next-token")
    sign_in(other, platform)
    agent.get("/")
    expect(agent.response.status).to eq(401)
  end

  it "изолирует магазины и credentials при одинаковом ID сотрудника" do
    @other_platform = PlatformSimulator.new(id: 202, token: "install-b")
    other = browser
    install(agent)
    sign_in(agent, platform)
    install(other, domain: "shop-b.example.test", id: 202, token: "install-b")
    sign_in(other, @other_platform, domain: "shop-b.example.test", id: 202)
    agent.post("/probe", params: { shop: "shop-b.example.test", insales_id: 202 })
    expect(agent.response.status).to eq(303)
    agent.follow_redirect!
    expect(agent.response.body).to include("shop-a.example.test", "101")
    expect(agent.response.body).not_to include("shop-b.example.test")
    expect(Shop.order(:insales_id).map(&:api_password)).to eq([ platform.password, @other_platform.password ])
  ensure
    @other_platform&.stop
  end

  it "экранирует данные API в HTML" do
    install(agent)
    sign_in(agent, platform)
    platform.account_body = { "id" => 101, "title" => "<script>alert(1)</script>" }
    agent.post("/probe")
    expect(agent.response.status).to eq(303)
    agent.follow_redirect!
    expect(agent.response.body).to include("&lt;script&gt;")
    expect(agent.response.body).not_to include("<script>")
  end

  it "не принимает GET для кнопок и неизвестный магазин" do
    agent.get("/probe")
    expect(agent.response.status).to eq(404)
    agent.get("/install", params: { shop: "evil.example.test", insales_id: 101, token: "secret" })
    expect(agent.response.status).to eq(400)
    expect(Shop.count).to eq(0)
  end
end
