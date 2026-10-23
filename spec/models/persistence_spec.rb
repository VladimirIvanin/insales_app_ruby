require "rails_helper"

RSpec.describe "Хранение секретов" do
  let(:service) { Insales::Lifecycle.new }

  it "шифрует пароли кандидата и активного подключения без детерминизма" do
    service.install(shop: "shop-a.example.test", insales_id: 101, token: "install-a")
    first = InstallationCandidate.first
    service.install(shop: "shop-b.example.test", insales_id: 202, token: "install-a")
    second = InstallationCandidate.order(:id).last
    first_cipher = first.ciphertext_for(:api_password)
    expect(first.api_password).to eq(second.api_password)
    expect(first_cipher).not_to include(first.api_password)
    expect(first_cipher).not_to eq(second.ciphertext_for(:api_password))
    shop = Shop.create!(insales_id: first.insales_id, domain: first.domain)
    shop.update!(api_password: first.api_password)
    expect(shop.ciphertext_for(:api_password)).not_to include(first.api_password)
  end

  it "не сохраняет рабочий пароль в tombstone" do
    service.install(shop: "shop-a.example.test", insales_id: 101, token: "install-a")
    password = InstallationCandidate.first.api_password
    service.uninstall(shop: "shop-a.example.test", insales_id: 101, token: password)
    expect(InstallationCandidate.count).to eq(0)
    expect(RevokedCredential.first.attributes.values).not_to include(password)
    expect(RevokedCredential.first.credential_digest).to eq(Digest::SHA256.hexdigest(password))
    service.install(shop: "shop-a.example.test", insales_id: 101, token: "install-a")
    expect(InstallationCandidate.count).to eq(0)
  end

  it "не запускается без постоянных ключей вне тестового режима" do
    expect { Insales::Settings.new({}) }.to raise_error(ArgumentError, /INSALES_APP_ID/)
    values = ENV.to_h.merge("AR_ENCRYPTION_PRIMARY_KEY" => "")
    expect { Insales::Settings.new(values) }.to raise_error(ArgumentError, /AR_ENCRYPTION_PRIMARY_KEY/)
  end
end
