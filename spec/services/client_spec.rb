require "rails_helper"

RSpec.describe Insales::Client do
  let(:platform) { PlatformSimulator.new }
  let(:client) { described_class.new(shop: "shop-a.example.test", password: platform.password, test_url: platform.url) }
  after { platform.stop }

  it "передаёт Basic Auth и сохраняет все поля аккаунта и лимит" do
    response = client.account
    expect(response.data).to include("id" => 101, "extra" => { "enabled" => true })
    expect(response.usage_limit).to eq("1/300")
    request = platform.requests.pop
    expect(request).to include(method: "GET", path: "/admin/account.json", body: "")
    expect(request[:authorization]).to eq("Basic #{Base64.strict_encode64("test-app:#{platform.password}")}")
  end

  %w[orders products].each do |resource|
    singular = resource.singularize
    it "использует контракт list/get/count/update для #{resource}" do
      expect(client.public_send("list_#{resource}", page: 2, per_page: 50).data.first).to include("custom_field" => "preserved")
      expect(platform.requests.pop[:query]).to eq("page" => "2", "per_page" => "50")
      expect(client.public_send("get_#{singular}", 12).data).to eq("id" => 12)
      expect(platform.requests.pop).to include(path: "/admin/#{resource}/12.json", method: "GET")
      expect(client.public_send("count_#{resource}").data).to eq("count" => 7)
      expect(platform.requests.pop[:path]).to eq("/admin/#{resource}/count.json")
      expect(client.public_send("update_#{singular}", 12, { "title" => "Новое" }).data).to eq("id" => 12, "title" => "Новое")
      request = platform.requests.pop
      expect(request).to include(method: "PUT", path: "/admin/#{resource}/12.json")
      expect(JSON.parse(request[:body])).to eq(singular => { "title" => "Новое" })
    end
  end

  it "допускает пустой 204 при обновлении" do
    platform.update_status = 204
    expect(client.update_product(12, {}).data).to be_nil
  end

  [ 401, 403, 429, 500, 502, 302 ].each do |status|
    it "сохраняет HTTP #{status} без повторов и переходов" do
      platform.account_status = status
      platform.error_body = "<html>unavailable</html>" if status == 502
      expect { client.account }.to raise_error(Insales::ApiError) { |error| expect(error.status).to eq(status) }
      expect(platform.requests.size).to eq(1)
    end
  end

  [ [], nil, { "title" => "missing id" }, { "id" => "101" } ].each do |payload|
    it "отклоняет неверную форму account #{payload.inspect}" do
      platform.account_body = payload
      expect { client.account }.to raise_error(Insales::ResourceError)
    end
  end

  it "ограничивает ответ при чтении" do
    platform.account_body = { "id" => 101, "large" => "x" * (2 * 1024 * 1024) }
    expect { client.account }.to raise_error(Insales::ResourceError, /size/)
  end

  it "различает транспортный отказ" do
    platform.stop
    expect { client.account }.to raise_error(Insales::TransportError)
  end

  it "различает некорректный JSON и пустой ответ 429" do
    platform.raw_account_body = "{broken"
    expect { client.account }.to raise_error(Insales::ResourceError)
    platform.account_status = 429
    expect { client.account }.to raise_error(Insales::ApiError) { |error| expect(error.status).to eq(429) }
  end

  it "ограничивает полный запрос по времени" do
    platform.delay = 5.5
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { client.account }.to raise_error(Insales::TransportError)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5.5
  end

  it "соблюдает сокращённый бюджет проверки очереди установок" do
    platform.delay = 0.3
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { client.account(timeout: 0.05) }.to raise_error(Insales::TransportError)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.25
    expect(platform.requests.size).to eq(1)
  end

  it "не принимает усечённое тело" do
    platform.truncate = true
    expect { client.account }.to raise_error(Insales::TransportError)
  end

  it "не разрешает произвольный HTTP даже в тестах" do
    expect { described_class.new(shop: "shop-a.example.test", password: "secret", test_url: "http://evil.test") }.to raise_error(ArgumentError)
  end

  it "сохраняет JSON-ошибку и API-заголовки без секретов в сообщении исключения" do
    platform.account_status = 429
    platform.error_body = JSON.generate("status" => "error", "message" => "sensitive details")
    expect { client.account }.to raise_error(Insales::ApiError) do |error|
      expect(error.data).to eq("status" => "error", "message" => "sensitive details")
      expect(error.body).to include("sensitive details")
      expect(error.retry_after).to eq("1")
      expect(error.message).not_to include("sensitive details")
    end
  end

  it "ограничивает тело ошибки 64 KiB и допускает HTML вместо JSON" do
    platform.account_status = 502
    platform.error_body = "<html>" + "x" * (128 * 1024)
    expect { client.account }.to raise_error(Insales::ApiError) do |error|
      expect(error.body.bytesize).to eq(64 * 1024)
      expect(error.data).to be_nil
      expect(error.status).to eq(502)
    end
  end

  it "сохраняет ошибки полей при обновлении" do
    platform.update_status = 422
    expect { client.update_product(12, { "title" => "invalid" }) }.to raise_error(Insales::ApiError) do |error|
      expect(error.data).to include("title" => "invalid")
      expect(error.usage_limit).to eq("1/300")
    end
  end
end
