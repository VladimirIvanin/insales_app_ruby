require "uri"

module Insales
  class Settings
    attr_reader :app_id, :app_secret, :base_url, :allowed_shops, :primary_key, :key_salt

    def initialize(env)
      values = env.to_h
      @app_id = read_app_id(values)
      @app_secret = required(values, "INSALES_APP_SECRET")
      @base_url = read_base_url(values)
      @allowed_shops = read_allowed_shops(values)
      @primary_key = required(values, "AR_ENCRYPTION_PRIMARY_KEY", minimum: 32)
      @key_salt = required(values, "AR_ENCRYPTION_KEY_DERIVATION_SALT", minimum: 32)
      validate_independent_secrets!(values)
    end

    def authorize_shop(value)
      domain = Protocol.shop(value)
      raise Protocol::InvalidInput, "Shop is not allowed" unless allowed_shops.include?(domain)
      domain
    end

    def callback_url
      "#{base_url}/auth/callback"
    end

    private
      def read_app_id(values)
        value = required(values, "INSALES_APP_ID")
        raise ArgumentError, "Invalid INSALES_APP_ID" unless value.match?(/\A[a-zA-Z0-9_-]{1,128}\z/)
        value
      end

      def read_base_url(values)
        value = required(values, "APP_BASE_URL").delete_suffix("/")
        unless valid_origin?(URI(value))
          raise ArgumentError, "APP_BASE_URL must be an HTTPS origin (loopback HTTP is allowed in development)"
        end
        value
      end

      def valid_origin?(uri)
        return false unless uri.host.present? && uri.path.empty?
        return false if uri.userinfo || uri.query || uri.fragment
        return true if uri.scheme == "https"

        !Rails.env.production? && uri.scheme == "http" && %w[localhost 127.0.0.1].include?(uri.host)
      end

      def read_allowed_shops(values)
        domains = required(values, "ALLOWED_SHOPS").split(",").map { |domain| Protocol.shop(domain.strip) }.uniq
        raise ArgumentError, "ALLOWED_SHOPS is empty" if domains.empty?
        domains.freeze
      end

      def validate_independent_secrets!(values)
        cookie_key = required(values, "SECRET_KEY_BASE", minimum: 64)
        unless [ app_secret, primary_key, key_salt, cookie_key ].uniq.size == 4
          raise ArgumentError, "Application, cookie and encryption secrets must be independent"
        end
      end

      def required(values, name, minimum: 1)
        value = values[name].to_s
        raise ArgumentError, "Missing or invalid #{name}" if value.strip.empty? || value.bytesize < minimum
        value
      end
  end
end
