require "rails_helper"

RSpec.describe Insales::Protocol do
  vectors = JSON.parse(File.read(File.expand_path("../fixtures/protocol-vectors.json", __dir__)))
  installation = vectors.fetch("install")
  [ vectors.fetch("autologin"), *vectors.fetch("additional_autologin") ].each_with_index do |fields, index|
    it "совпадает с общими межъязыковыми векторами подписей #{index + 1}" do
      password = described_class.password(installation.fetch("token"), installation.fetch("secret"))
      expect(password).to eq(installation.fetch("expected_password"))
      user = { user_email: fields.fetch("email"), user_name: fields.fetch("name"), user_id: fields.fetch("user_id") }
      expect(described_class.token(fields.fetch("nonce"), password: password)).to eq(fields.fetch("expected_token"))
      expect(described_class.token2(fields.fetch("nonce"), **user, password: password)).to eq(fields.fetch("expected_token2"))
      expect(described_class.token3(fields.fetch("nonce"), **user, email_confirmed: fields.fetch("email_confirmed"), password: password))
        .to eq(fields.fetch("expected_token3"))
    end
  end

  it "вычисляет пароль по независимому вектору" do
    expect(described_class.password("a1b2c3d4e5f6g7h8i9j0", "test-secret-key")).to eq("49a3b2a6596e83b615c7a667249448b7")
  end

  it "сохраняет UTF-8 и порядок полей token3" do
    signature = described_class.token3("demo-login-nonce", user_email: "user@example.invalid",
      user_name: "Тестовый партнёр", user_id: "42", email_confirmed: "false",
      password: "2b6479b65a8456e70c98779838646881")
    expect(signature).to eq("0f73f440da4b86d8be62f3e19b57c77e")
  end

  it "отклоняет пути, порты, IP и поддомены злоумышленника" do
    [ "https://shop.example.test", "shop.example.test/a", "shop.example.test:443", "127.0.0.1", "a..test", "a.test." ].each do |domain|
      expect { described_class.shop(domain) }.to raise_error(ArgumentError)
    end
    expect { Rails.configuration.x.insales.authorize_shop("shop-a.example.test.evil.test") }.to raise_error(ArgumentError)
    expect(Rails.configuration.x.insales.authorize_shop("SHOP-A.EXAMPLE.TEST")).to eq("shop-a.example.test")
  end
end
