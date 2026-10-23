require "rails_helper"

RSpec.describe "Параметры и журналы callback", type: :request do
  let(:platform) { PlatformSimulator.new }
  let(:agent) { browser }
  before { connect_platform(platform) }
  after { platform.stop }

  %w[token3 user_email user_id email_confirmed].each do |missing|
    it "возвращает 400 при отсутствии #{missing} после начала входа" do
      install(agent)
      callback = begin_login(agent, platform)
      fields = URI.decode_www_form(callback.query).to_h.except(missing)
      agent.get(callback.path, params: fields)
      expect(agent.response.status).to eq(400)
      expect(AppSession.count).to eq(0)
      expect(LoginChallenge.count).to eq(1)
    end
  end

  %w[user_email user_name].each do |field|
    [ "", nil ].each do |value|
      context "когда #{field} сотрудника равен #{value.inspect}" do
        let(:platform) { PlatformSimulator.new(**{ field.to_sym => value }, email_confirmed: "false") }

        it "принимает исходный URI подписанного callback и открывает страницу подключения" do
          install(agent)
          callback = begin_login(agent, platform)
          wire_field = value.nil? ? field : "#{field}="
          expect(callback.query.split("&")).to include(wire_field)

          agent.get(callback.request_uri)

          expect(agent.response.status).to eq(303)
          expect(AppSession.first.callback_user_id).to eq(42)
          expect(AppSession.first.shop.insales_id).to eq(101)
          expect(LoginChallenge.count).to eq(0)
          agent.follow_redirect!
          expect(agent.response.status).to eq(200)
          expect(agent.response.body).to include("shop-a.example.test", "ID сотрудника из callback")
        end

        it "отклоняет подмену поля и позволяет повторить исходный callback" do
          install(agent)
          callback = begin_login(agent, platform)
          fields = URI.decode_www_form(callback.query).to_h.merge(field => "other@example.invalid")

          agent.get(callback.path, params: fields)

          expect(agent.response.status).to eq(403)
          expect(AppSession.count).to eq(0)
          expect(LoginChallenge.count).to eq(1)
          agent.get(callback.request_uri)
          expect(agent.response.status).to eq(303)
        end

        it "отклоняет чужой браузер и повторное использование callback" do
          install(agent)
          callback = begin_login(agent, platform)

          stranger = browser
          stranger.get(callback.request_uri)

          expect(stranger.response.status).to eq(403)
          expect(AppSession.count).to eq(0)
          expect(LoginChallenge.count).to eq(1)
          agent.get(callback.request_uri)
          expect(agent.response.status).to eq(303)
          agent.get(callback.request_uri)
          expect(agent.response.status).to eq(403)
          expect(AppSession.count).to eq(1)
        end
      end
    end

    [ [ "user@example.invalid" ], { "value" => "user@example.invalid" }, "a" * 1025 ].each do |value|
      it "возвращает 400 при неверном #{field} (#{value.class}, #{value.size})" do
        install(agent)
        callback = begin_login(agent, platform)
        fields = URI.decode_www_form(callback.query).to_h.merge(field => value)

        agent.get(callback.path, params: fields)

        expect(agent.response.status).to eq(400)
        expect(AppSession.count).to eq(0)
        expect(LoginChallenge.count).to eq(1)
      end
    end
  end

  it "отклоняет boolean вместо имени, не нормализуя его в пустую строку" do
    install(agent)
    callback = begin_login(agent, platform)
    fields = URI.decode_www_form(callback.query).to_h.merge("user_name" => false)

    agent.get(callback.path, params: fields, as: :json)

    expect(agent.response.status).to eq(400)
    expect(AppSession.count).to eq(0)
    expect(LoginChallenge.count).to eq(1)
  end

  it "принимает отсутствующее имя с подписью для пустой строки" do
    platform.stop
    anonymous = PlatformSimulator.new(user_name: nil)
    connect_platform(anonymous)
    install(agent)
    callback = begin_login(agent, anonymous)
    callback.query = callback.query.split("&").reject { |field| field == "user_name" }.join("&")

    agent.get(callback.request_uri)

    expect(agent.response.status).to eq(303)
    expect(AppSession.first.callback_user_id).to eq(42)
    expect(LoginChallenge.count).to eq(0)
    agent.get(callback.request_uri)
    expect(agent.response.status).to eq(403)
  ensure
    anonymous&.stop
  end

  [ "flow[]=1", "flow[value]=1", "flow[]", "flow=", "flow=abc" ].each do |query|
    it "отклоняет нестроковый или неверный flow: #{query}" do
      install(agent)
      callback = begin_login(agent, platform)
      original = callback.query.split("&").reject { |field| field.start_with?("flow=") }.join("&")

      agent.get("#{callback.path}?#{original}&#{query}")

      expect(agent.response.status).to eq(403)
      expect(AppSession.count).to eq(0)
      expect(LoginChallenge.count).to eq(1)
      agent.get(callback.request_uri)
      expect(agent.response.status).to eq(303)
    end
  end

  [ "flow[]=1", "flow[value]=1" ].each do |query|
    it "сохраняет 403 для вложенного flow при Accept: application/json (#{query})" do
      agent.get("/auth/callback?#{query}", headers: { "Accept" => "application/json" })

      expect(agent.response.status).to eq(403)
      expect(agent.response.media_type).to eq("text/html")
      expect(AppSession.count).to eq(0)
    end
  end

  it "показывает ID как callback-метаданные при неоднозначных границах token3" do
    platform.stop
    ambiguous = PlatformSimulator.new(user_name: "N")
    connect_platform(ambiguous)
    install(agent)
    callback = begin_login(agent, ambiguous)
    fields = URI.decode_www_form(callback.query).to_h.merge("user_name" => "N4", "user_id" => "2")

    agent.get(callback.path, params: fields)

    expect(agent.response.status).to eq(303)
    expect(AppSession.first.callback_user_id).to eq(2)
    agent.follow_redirect!
    expect(agent.response.body).to include("ID сотрудника из callback", "не удостоверяют личность отдельно", "не используются для персональных прав")
    expect(agent.response.body).to include("<dd>2</dd>")
  ensure
    ambiguous&.stop
  end

  it "фильтрует секреты установки, nonce и token3 в настоящем Rails-логе" do
    logfile = Rails.root.join("log/test.log")
    offset = File.size?(logfile) || 0
    token = SecureRandom.hex(24)
    platform.rotate(token)
    install(agent, token: token)
    callback = begin_login(agent, platform)
    nonce = LoginChallenge.first.nonce
    token3 = URI.decode_www_form(callback.query).to_h.fetch("token3")
    agent.get(callback.request_uri)
    expect(agent.response.status).to eq(303)
    logs = File.binread(logfile).byteslice(offset..).force_encoding("UTF-8")
    expect(logs).to include("ConnectionsController", "[FILTERED]")
    expect(logs).not_to include(token, nonce, token3, platform.password, "test-app-secret")
  end
end
