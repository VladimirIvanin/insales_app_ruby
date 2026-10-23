require "puma"
require "socket"
require "base64"
require "digest"

class PlatformSimulator
  attr_reader :url, :requests, :server
  attr_accessor :account_status, :account_body, :usage, :update_status, :delay, :truncate, :raw_account_body, :error_body

  def initialize(id: 101, token: "install-a")
    @id = id
    @requests = Queue.new
    @usage = "1/300"
    @account_status = 200
    @update_status = 200
    @delay = 0
    @account_body = { "id" => id, "title" => "Тестовый магазин", "extra" => { "enabled" => true } }
    rotate(token)
    @server = Puma::Server.new(method(:call), nil, min_threads: 0, max_threads: 4)
    listener = @server.add_tcp_listener("127.0.0.1", 0)
    @url = "http://127.0.0.1:#{listener.addr[1]}"
    @server.run
  end

  def rotate(token)
    @password = Digest::MD5.hexdigest(token + "test-app-secret")
  end

  def password
    @password.dup
  end

  def stop
    @release << true if @release
    @server.stop(true)
  end

  def hold_account
    @started = Queue.new
    @release = Queue.new
    @hold_next = true
  end

  def wait_for_account
    Timeout.timeout(3) { @started.pop }
  end

  def release_account
    @release << true
  end

  def call(env)
    request = Rack::Request.new(env)
    @requests << { method: request.request_method, path: request.path, query: request.GET,
      body: request.body.read, authorization: env["HTTP_AUTHORIZATION"] }
    if request.path == "/admin/applications/test-app/login"
      return login(request)
    end
    if request.path == "/admin/account.json" && (@account_status == 429 || @account_status >= 500)
      return [ @account_status, { "retry-after" => "1" }, [ @error_body || "" ] ]
    end
    expected = "Basic #{Base64.strict_encode64("test-app:#{@password}")}"
    return [ 401, {}, [ "Unauthorized" ] ] unless env["HTTP_AUTHORIZATION"] == expected
    if request.path == "/admin/account.json" && request.get?
      status, body = @account_status, @raw_account_body || JSON.generate(@account_body)
      if @hold_next
        release = @release
        @hold_next = false
        @started << true
        release.pop
      end
      sleep @delay if @delay.positive?
      headers = { "content-type" => "application/json", "api-usage-limit" => @usage }
      headers["location"] = "#{@url}/redirect-target" if (300..399).cover?(status)
      headers["content-length"] = (body.bytesize + 100).to_s if @truncate
      return [ status, headers, [ body ] ]
    end
    if request.get? && request.path.match?(%r{\A/admin/(orders|products)/count\.json\z})
      return json(200, { "count" => 7 })
    end
    if request.get? && request.path.match?(%r{\A/admin/(orders|products)\.json\z})
      return json(200, [ { "id" => 12, "custom_field" => "preserved" } ])
    end
    if (match = request.path.match(%r{\A/admin/(orders|products)/(\d+)\.json\z}))
      return json(200, { "id" => match[2].to_i }) if request.get?
      if request.put?
        return json(422, { "message" => "Expected application/json" }) unless request.media_type == "application/json"
        payload = JSON.parse(env["rack.input"].tap(&:rewind).read)
        root = match[1] == "orders" ? "order" : "product"
        return [ 422, {}, [ "Invalid root" ] ] unless payload.keys == [ root ] && payload[root].is_a?(Hash)
        return [ 204, {}, [] ] if @update_status == 204
        return json(@update_status, payload[root].merge("id" => match[2].to_i))
      end
    end
    [ 404, {}, [ "Unknown simulator endpoint" ] ]
  end

  def login(request)
    nonce = request.params.fetch("token")
    fields = { "user_email" => "user@example.invalid", "user_name" => "Тестовый сотрудник", "user_id" => "42", "email_confirmed" => "true" }
    signature = Digest::MD5.hexdigest(nonce + fields.values.join + @password)
    callback = URI(request.params.fetch("login"))
    return [ 422, {}, [ "Invalid callback host" ] ] unless callback.host == "app.example.test"
    callback.query = URI.encode_www_form(fields.merge("token3" => signature))
    [ 302, { "location" => callback.to_s }, [] ]
  end

  def json(status, payload)
    [ status, { "content-type" => "application/json", "api-usage-limit" => @usage }, [ JSON.generate(payload) ] ]
  end
end
