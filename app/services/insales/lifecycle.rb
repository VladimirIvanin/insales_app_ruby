module Insales
  class Lifecycle
    CANDIDATE_TTL = 7.days
    CANDIDATE_LIMIT = 5
    ADMISSION_TIMEOUT = 3
    CHALLENGE_TTL = 5.minutes
    Context = Data.define(:session, :shop)
    Login = Data.define(:challenge, :redirect_url)
    Grant = Data.define(:token, :session)

    class Failure < StandardError
      attr_reader :status, :code

      def initialize(code, status)
        @code, @status = code, status
        super(code.to_s)
      end
    end

    def initialize(settings: Rails.configuration.x.insales, client_factory: nil)
      @settings = settings
      @client_factory = client_factory || ->(shop, password) { Client.new(shop: shop, password: password, app_id: settings.app_id) }
    end

    def install(shop:, insales_id:, token:)
      domain, id = identity(shop, insales_id)
      installations.install(domain: domain, id: id, token: token)
    end

    def begin_login(shop:, insales_id:, browser_token:)
      domain, id = identity(shop, insales_id)
      status = installations.verify_and_activate(domain, id)
      logins.begin_login(domain: domain, id: id, browser_token: browser_token, verification_status: status)
    end

    def complete_login(**fields)
      logins.complete_login(**fields)
    end

    def authenticate(token)
      Sessions.new(settings: @settings).authenticate(token)
    end

    def logout(token)
      AppSession.where(token_digest: Digest::SHA256.hexdigest(token)).delete_all if token.present?
    end

    def uninstall(shop:, insales_id:, token:)
      domain, id = identity(shop, insales_id)
      Uninstalls.new.call(domain: domain, id: id, token: token)
    end

    def client(store)
      raise ShopNotAllowed unless @settings.allowed_shops.include?(store.domain)
      @client_factory.call(store.domain, store.api_password)
    end

    private
      def identity(shop, insales_id)
        [ @settings.authorize_shop(shop), Protocol.identifier(insales_id) ]
      end

      def installations
        @installations ||= Installations.new(settings: @settings, client_factory: @client_factory)
      end

      def logins
        @logins ||= Logins.new(settings: @settings)
      end
  end
end
