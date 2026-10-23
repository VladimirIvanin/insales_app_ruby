require "rails_helper"

RSpec.describe Insales::Settings do
  let(:values) do
    {
      "INSALES_APP_ID" => "partner-app", "INSALES_APP_SECRET" => "app-secret",
      "APP_BASE_URL" => "https://app.example.test/",
      "ALLOWED_SHOPS" => " SHOP-A.EXAMPLE.TEST,shop-b.example.test,shop-a.example.test ",
      "AR_ENCRYPTION_PRIMARY_KEY" => "primary-key-" * 4,
      "AR_ENCRYPTION_KEY_DERIVATION_SALT" => "key-salt-" * 4,
      "SECRET_KEY_BASE" => "cookie-key-" * 8
    }
  end

  it "читает значения и нормализует URL и разрешённые магазины" do
    settings = described_class.new(values)

    expect(settings.app_id).to eq("partner-app")
    expect(settings.app_secret).to eq("app-secret")
    expect(settings.base_url).to eq("https://app.example.test")
    expect(settings.callback_url).to eq("https://app.example.test/auth/callback")
    expect(settings.allowed_shops).to eq([ "shop-a.example.test", "shop-b.example.test" ])
    expect(settings.allowed_shops).to be_frozen
    expect(settings.primary_key).to eq(values.fetch("AR_ENCRYPTION_PRIMARY_KEY"))
    expect(settings.key_salt).to eq(values.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT"))
  end

  it "не подменяет отсутствующие настройки тестовыми значениями" do
    expect { described_class.new({}) }.to raise_error(ArgumentError, /INSALES_APP_ID/)
  end

  it "отклоняет некорректный идентификатор приложения" do
    values["INSALES_APP_ID"] = "partner/app"

    expect { described_class.new(values) }.to raise_error(ArgumentError, "Invalid INSALES_APP_ID")
  end

  it "отклоняет URL с путём, query, fragment, credentials и внешний HTTP" do
    [ "https://app.example.test/path", "https://app.example.test?query=1",
      "https://app.example.test#fragment", "https://user:password@app.example.test",
      "http://app.example.test" ].each do |url|
      expect { described_class.new(values.merge("APP_BASE_URL" => url)) }
        .to raise_error(ArgumentError, /APP_BASE_URL must be an HTTPS origin/)
    end
  end

  it "допускает loopback HTTP вне production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

    [ "http://localhost:8765", "http://127.0.0.1:8765" ].each do |url|
      expect(described_class.new(values.merge("APP_BASE_URL" => url)).base_url).to eq(url)
    end
  end

  it "требует HTTPS даже для loopback в production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    expect { described_class.new(values.merge("APP_BASE_URL" => "http://127.0.0.1:8765")) }
      .to raise_error(ArgumentError, /APP_BASE_URL must be an HTTPS origin/)
  end

  it "отклоняет пустой список магазинов" do
    values["ALLOWED_SHOPS"] = ",,,"

    expect { described_class.new(values) }.to raise_error(ArgumentError, "ALLOWED_SHOPS is empty")
  end

  {
    "AR_ENCRYPTION_PRIMARY_KEY" => 32,
    "AR_ENCRYPTION_KEY_DERIVATION_SALT" => 32,
    "SECRET_KEY_BASE" => 64
  }.each do |name, minimum|
    it "проверяет минимальную длину #{name}" do
      values[name] = "x" * (minimum - 1)

      expect { described_class.new(values) }.to raise_error(ArgumentError, "Missing or invalid #{name}")
    end
  end

  it "требует независимые секреты приложения, cookie и шифрования" do
    values["AR_ENCRYPTION_KEY_DERIVATION_SALT"] = values.fetch("AR_ENCRYPTION_PRIMARY_KEY")

    expect { described_class.new(values) }
      .to raise_error(ArgumentError, "Application, cookie and encryption secrets must be independent")
  end
end
