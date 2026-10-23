require "rails_helper"

RSpec.describe "Контракты маршрутов", type: :request do
  let(:agent) { browser }

  it "отвечает на health и отклоняет неизвестные пути и методы" do
    agent.get("/healthz")
    expect(agent.response.status).to eq(200)
    [ [ :get, "/missing" ], [ :post, "/healthz" ], [ :post, "/install" ], [ :get, "/probe" ], [ :get, "/logout" ] ].each do |method, path|
      agent.public_send(method, path)
      expect(agent.response.status).to eq(404)
    end
  end

  %w[shop insales_id token].each do |missing|
    %w[install uninstall].each do |action|
      it "возвращает 400 при отсутствии #{missing} в #{action}" do
        fields = { "shop" => "shop-a.example.test", "insales_id" => "101", "token" => "install-a" }
        agent.get("/#{action}", params: fields.except(missing))
        expect(agent.response.status).to eq(400)
      end
    end
  end

  it "различает неустановленный, запрещённый и неизвестный удаляемый магазин" do
    agent.get("/login", params: { shop: "shop-a.example.test", insales_id: 101 })
    expect(agent.response.status).to eq(401)
    agent.get("/login", params: { shop: "unknown.example.test", insales_id: 101 })
    expect(agent.response.status).to eq(400)
    agent.get("/uninstall", params: { shop: "shop-a.example.test", insales_id: 101, token: "0" * 32 })
    expect(agent.response.status).to eq(403)
  end
end
