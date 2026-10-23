require "rails_helper"

RSpec.describe "Штатная фабрика клиента", type: :request do
  it "использует настоящий конструктор клиента без тестовой настройки config.x" do
    expect(Rails.configuration.x.insales_client_factory).to be_nil
    agent = browser
    install(agent)
    password = Digest::MD5.hexdigest("install-a" + "test-app-secret")
    account = Struct.new(:data).new({ "id" => 101 })
    client = instance_double(Insales::Client, account: account)
    expect(Insales::Client).to receive(:new).with(shop: "shop-a.example.test", password: password, app_id: "test-app").and_return(client)
    agent.get("/login", params: { shop: "shop-a.example.test", insales_id: 101 })
    expect(agent.response.status).to eq(302)
    expect(Shop.find_by!(insales_id: 101)).to be_active
  end
end
