module Insales
  class Logins
    def initialize(settings:)
      @settings = settings
    end

    def begin_login(domain:, id:, browser_token:, verification_status:)
      Shop.transaction do
        store = Shop.lock.find_by(insales_id: id, domain: domain)
        unless store&.active?
          code, status = verification_status == :unavailable ? [ :verification_unavailable, 503 ] : [ :not_installed, 401 ]
          raise Lifecycle::Failure.new(code, status)
        end
        store.login_challenges.where("expires_at <= ?", Time.current).delete_all
        challenge = store.login_challenges.create!(generation: store.generation,
          nonce: SecureRandom.hex(32), browser_digest: Digest::SHA256.hexdigest(browser_token),
          expires_at: Lifecycle::CHALLENGE_TTL.from_now)
        query = URI.encode_www_form(token: challenge.nonce, login: "#{@settings.callback_url}?#{URI.encode_www_form(flow: challenge.id)}")
        url = "https://#{store.domain}/admin/applications/#{@settings.app_id}/login?#{query}"
        Lifecycle::Login.new(challenge: challenge, redirect_url: url)
      end
    end

    def complete_login(challenge_id:, browser_token:, token3:, user_email:, user_name:, user_id:, email_confirmed:)
      fields = { user_email: user_email, user_name: user_name, user_id: user_id, email_confirmed: email_confirmed }
      id = Protocol.validate_user_fields!(**fields)
      Shop.transaction do
        challenge = LoginChallenge.find_by(id: challenge_id)
        raise Lifecycle::Failure.new(:invalid_challenge, 403) unless challenge
        store = Shop.lock.find(challenge.shop_id)
        validate_challenge!(challenge, store, browser_token)
        expected = Protocol.token3(challenge.nonce, **fields, password: store.api_password)
        raise Lifecycle::Failure.new(:invalid_signature, 403) unless Protocol.matches?(expected, token3)
        consumed = LoginChallenge.where(id: challenge.id, generation: store.generation)
          .where("expires_at > ?", Time.current).delete_all
        raise Lifecycle::Failure.new(:invalid_challenge, 403) unless consumed == 1
        token = SecureRandom.hex(32)
        record = store.app_sessions.create!(generation: store.generation, user_id: id,
          token_digest: Digest::SHA256.hexdigest(token), last_seen_at: Time.current,
          expires_at: AppSession::ABSOLUTE_TIMEOUT.from_now)
        Lifecycle::Grant.new(token: token, session: record)
      end
    end

    private
      def validate_challenge!(challenge, store, browser_token)
        browser_digest = Digest::SHA256.hexdigest(browser_token)
        valid = challenge.expires_at > Time.current && store.active? && store.generation == challenge.generation &&
          @settings.allowed_shops.include?(store.domain) &&
          ActiveSupport::SecurityUtils.secure_compare(challenge.browser_digest, browser_digest)
        raise Lifecycle::Failure.new(:invalid_challenge, 403) unless valid
      end
  end
end
