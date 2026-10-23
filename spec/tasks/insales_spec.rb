require "rails_helper"
require "stringio"

RSpec.describe "Диагностика и очистка" do
  let(:platform) { PlatformSimulator.new }
  before(:context) { Rails.application.load_tasks }
  before { connect_platform(platform) }
  after { platform.stop }

  def run_task(name)
    original_stdout, original_stderr = $stdout, $stderr
    $stdout, $stderr = StringIO.new, StringIO.new
    status = 0
    Rake::Task[name].reenable
    begin
      Rake::Task[name].invoke
    rescue SystemExit => error
      status = error.status
    end
    [ status, $stdout.string, $stderr.string ]
  ensure
    $stdout, $stderr = original_stdout, original_stderr
  end

  it "продолжает doctor после запрещённого магазина, возвращает ошибку и не печатает пароль" do
    agent = browser
    install(agent)
    sign_in(agent, platform)
    @other_platform = PlatformSimulator.new(id: 202, token: "install-b")
    other = browser
    install(other, domain: "shop-b.example.test", id: 202, token: "install-b")
    sign_in(other, @other_platform, domain: "shop-b.example.test", id: 202)
    allow(Rails.configuration.x.insales).to receive(:allowed_shops).and_return([ "shop-b.example.test" ])

    status, output, error = run_task("insales:doctor")

    expect(status).not_to eq(0)
    expect(output).to include("shop-b.example.test: ok")
    expect(error).to include("shop-a.example.test: not allowed")
    expect(output + error).not_to include(platform.password, @other_platform.password, "test-app-secret")
  ensure
    @other_platform&.stop
  end

  it "очищает истёкшие записи и сохраняет действующий pending" do
    agent = browser
    install(agent)
    sign_in(agent, platform)
    install(agent, token: "pending")
    old_password = platform.password
    agent.get("/uninstall", params: { shop: "shop-a.example.test", insales_id: 101, token: old_password })
    travel 31.days
    install(agent, token: "fresh")
    status, output, error = run_task("insales:cleanup")
    expect(status).to eq(0)
    expect(error).to be_empty
    expect(output).to include("revocations: 1")
    expect(RevokedCredential.count).to eq(0)
    expect(InstallationCandidate.count).to eq(1)
    expect(InstallationCandidate.first.api_password).to eq(Digest::MD5.hexdigest("freshtest-app-secret"))
  end
end
