module BrowserFlow
  def browser
    ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host! "app.example.test"
      session.https!
    end
  end

  def connect_platform(platform, domain = "shop-a.example.test")
    Rails.configuration.x.insales_client_factory = ->(shop, password) do
      origin = shop == domain ? platform.url : @other_platform&.url
      Insales::Client.new(shop: shop, password: password, test_url: origin)
    end
  end

  def install(browser, token: "install-a", domain: "shop-a.example.test", id: 101)
    browser.get("/install", params: { shop: domain, insales_id: id, token: token })
    expect(browser.response.status).to eq(200)
  end

  def begin_login(browser, platform, domain: "shop-a.example.test", id: 101)
    browser.get("/login", params: { shop: domain, insales_id: id, user_id: "999" })
    expect(browser.response.status).to eq(302)
    outgoing = URI(browser.response.location)
    expect(outgoing.host).to eq(domain)
    expect(outgoing.path).to eq("/admin/applications/test-app/login")
    response = Net::HTTP.get_response(URI(platform.url + outgoing.request_uri))
    expect(response.code).to eq("302")
    URI(response["location"])
  end

  def sign_in(browser, platform, **options)
    callback = begin_login(browser, platform, **options)
    browser.get(callback.request_uri)
    expect(browser.response.status).to eq(303)
    browser.get("/")
    expect(browser.response.status).to eq(200)
    callback
  end

  def csrf(browser)
    browser.response.body[/name="csrf-token" content="([^"]+)"/, 1]
  end
end
