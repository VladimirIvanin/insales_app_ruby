require "rails_helper"

RSpec.describe "Конкурентные callbacks" do
  let(:platform) { PlatformSimulator.new }
  let(:factory) { ->(domain, password) { Insales::Client.new(shop: domain, password: password, test_url: platform.url) } }
  let(:service) { Insales::Lifecycle.new(client_factory: factory) }
  let(:identity) { { shop: "shop-a.example.test", insales_id: 101 } }
  after { platform.stop }

  it "проверяет кандидата один раз при двух одновременных login" do
    service.install(**identity, token: "install-a")
    platform.hold_account
    pending = login_thread
    platform.wait_for_account

    other = login_thread.value
    expect(other).to be_a(Insales::Lifecycle::Failure)
    expect(other.status).to eq(503)
    expect(platform.requests.size).to eq(1)
    platform.release_account
    expect(pending.value).to be_a(Insales::Lifecycle::Login)
    generation = Shop.first.generation
    service.begin_login(**identity, browser_token: "second-browser")
    expect(Shop.first.generation).to eq(generation)
    expect(platform.requests.size).to eq(1)
    expect(LoginChallenge.count).to eq(2)
  ensure
    platform.release_account if pending&.alive?
    pending&.join(6)
  end

  it "оставляет свободный веб-поток при двух медленных API-проверках" do
    other_platform = PlatformSimulator.new(id: 202, token: "install-b")
    factory = ->(domain, password) do
      origin = domain == identity[:shop] ? platform.url : other_platform.url
      Insales::Client.new(shop: domain, password: password, test_url: origin)
    end
    bounded = Insales::Lifecycle.new(client_factory: factory)
    identities = [ identity, { shop: "shop-b.example.test", insales_id: 202 } ]
    identities.zip(%w[install-a install-b]).each { |fields, token| bounded.install(**fields, token: token) }
    [ platform, other_platform ].each(&:hold_account)
    threads = identities.map do |fields|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { bounded.begin_login(**fields, browser_token: "browser") }
      end
    end
    [ platform, other_platform ].each(&:wait_for_account)

    bounded.install(**identity, token: "next-token")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { bounded.begin_login(**identity, browser_token: "third-browser") }
      .to raise_error(Insales::Lifecycle::Failure) { |error| expect(error.status).to eq(503) }
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.5
    expect(platform.requests.size + other_platform.requests.size).to eq(2)
    [ platform, other_platform ].each(&:release_account)
    threads.each(&:value)
  ensure
    [ platform, other_platform ].compact.each { |server| server.release_account if threads&.any?(&:alive?) }
    threads&.each { |thread| thread.join(6) }
    other_platform&.stop
  end

  def login_thread
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        service.begin_login(**identity, browser_token: "browser")
      rescue Insales::Lifecycle::Failure => error
        error
      end
    end
  end

  it "сохраняет разные одновременные install без потери кандидатов" do
    ready, go = Queue.new, Queue.new
    threads = %w[install-a install-b].map do |token|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          service.install(**identity, token: token)
        end
      end
    end
    2.times { Timeout.timeout(3) { ready.pop } }
    2.times { go << true }
    threads.each(&:value)

    expect(Shop.count).to eq(0)
    expect(InstallationCandidate.count).to eq(2)
    expect(InstallationCandidate.pluck(:credential_digest).uniq.size).to eq(2)
    expect(platform.requests.size).to eq(0)
    latest_password = InstallationCandidate.order(:id).last.api_password
    latest_token = %w[install-a install-b].find { |token| Digest::MD5.hexdigest(token + "test-app-secret") == latest_password }
    platform.rotate(latest_token)
    browser_agent = browser
    connect_platform(platform)
    sign_in(browser_agent, platform)
    expect(Shop.first.api_password).to eq(platform.password)
  ensure
    threads&.each { |thread| thread.join(6) }
  end

  it "не удерживает write-транзакцию и не откатывает активацию во время admission" do
    service.install(**identity, token: "install-a")
    4.times { |index| service.install(shop: identity[:shop], insales_id: 999, token: "fake-#{index}") }
    platform.hold_account
    pending = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        service.install(shop: identity[:shop], insales_id: 999, token: "overflow")
      end
    end
    platform.wait_for_account

    expect do
      service.begin_login(**identity, browser_token: "browser")
    end.to raise_error(Insales::Lifecycle::Failure) { |error| expect(error.status).to eq(503) }
    service.install(**identity, token: "install-a")
    platform.release_account
    pending.value
    service.begin_login(**identity, browser_token: "browser")

    expect(Shop.first.api_password).to eq(platform.password)
    expect(InstallationCandidate.count).to be <= Insales::Lifecycle::CANDIDATE_LIMIT
    expect(LoginChallenge.count).to eq(1)
  ensure
    platform.release_account if pending&.alive?
    pending&.join(6)
  end

  it "восстанавливает challenge при сбое создания сессии и допускает повтор callback" do
    service.install(**identity, token: "install-a")
    result = service.begin_login(**identity, browser_token: "browser")
    reply = Net::HTTP.get_response(URI(platform.url + URI(result.redirect_url).request_uri))
    fields = URI.decode_www_form(URI(reply["location"]).query).to_h.except("flow").symbolize_keys
    allow_any_instance_of(AppSession).to receive(:save!).and_raise(ActiveRecord::RecordNotSaved, "simulated failure")

    expect do
      service.complete_login(**fields, challenge_id: result.challenge.id, browser_token: "browser")
    end.to raise_error(ActiveRecord::RecordNotSaved)

    expect(LoginChallenge.exists?(result.challenge.id)).to be(true)
    expect(AppSession.count).to eq(0)
    allow_any_instance_of(AppSession).to receive(:save!).and_call_original
    grant = service.complete_login(**fields, challenge_id: result.challenge.id, browser_token: "browser")
    expect(service.authenticate(grant.token).session.user_id).to eq(42)
    expect(LoginChallenge.count).to eq(0)
  end

  it "не активирует старый ответ после более новой подтверждённой установки" do
    service.install(**identity, token: "install-a")
    platform.hold_account
    old = login_thread
    platform.wait_for_account
    platform.rotate("install-b")
    service.install(**identity, token: "install-b")
    service.begin_login(**identity, browser_token: "new-browser")
    new_generation = Shop.first.generation
    platform.release_account
    expect(old.value).to be_a(Insales::Lifecycle::Login)
    expect(Shop.first.api_password).to eq(platform.password)
    expect(Shop.first.generation).to eq(new_generation)
  ensure
    platform.release_account if old&.alive?
    old&.join(6)
  end

  it "не восстанавливает кандидата после uninstall во время API-запроса" do
    service.install(**identity, token: "install-a")
    platform.hold_account
    pending = login_thread
    platform.wait_for_account
    service.uninstall(**identity, token: platform.password)
    platform.release_account
    expect(pending.value).to be_a(Insales::Lifecycle::Failure)
    expect(Shop.where.not(api_password: nil).count).to eq(0)
    expect(InstallationCandidate.count).to eq(0)
    expect(LoginChallenge.count).to eq(0)
  ensure
    platform.release_account if pending&.alive?
    pending&.join(6)
  end

  it "создаёт ровно одну сессию при двух одновременных callback" do
    service.install(**identity, token: "install-a")
    result = service.begin_login(**identity, browser_token: "browser")
    callback = URI(platform.url + URI(result.redirect_url).request_uri)
    reply = Net::HTTP.get_response(callback)
    fields = URI.decode_www_form(URI(reply["location"]).query).to_h.except("flow").symbolize_keys
    ready, go = Queue.new, Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          service.complete_login(**fields, challenge_id: result.challenge.id, browser_token: "browser")
        rescue Insales::Lifecycle::Failure => error
          error
        end
      end
    end
    2.times { Timeout.timeout(3) { ready.pop } }
    2.times { go << true }
    results = threads.map(&:value)
    expect(results.count { |value| value.is_a?(Insales::Lifecycle::Grant) }).to eq(1)
    expect(results.count { |value| value.is_a?(Insales::Lifecycle::Failure) }).to eq(1)
    expect(AppSession.count).to eq(1)
    expect(LoginChallenge.count).to eq(0)
  ensure
    threads&.each { |thread| thread.join(6) }
  end
end
