require "digest"

module Insales
  module Protocol
    class InvalidInput < ArgumentError; end

    module_function

    def shop(value)
      domain = value.to_s.downcase
      labels = domain.split(".", -1)
      valid = domain.bytesize <= 253 && labels.size >= 2 &&
        labels.all? { |label| label.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/) } &&
        labels.last.match?(/[a-z]/)
      raise InvalidInput, "Invalid shop domain" unless valid
      domain
    end

    def identifier(value)
      text = value.to_s
      raise InvalidInput, "Invalid identifier" unless text.match?(/\A[1-9][0-9]{0,18}\z/) && text.to_i <= 2**63 - 1
      text.to_i
    end

    def password(token, secret)
      Digest::MD5.hexdigest(token + secret)
    end

    def validate_user_fields!(user_email:, user_name:, user_id:, email_confirmed:)
      values = [ user_email, user_name, user_id, email_confirmed ]
      raise InvalidInput, "Invalid user fields" unless values.all? { |value| value.is_a?(String) }
      raise InvalidInput, "Invalid confirmation flag" unless %w[true false].include?(email_confirmed)
      raise InvalidInput, "Invalid user fields" if user_email.empty? || [ user_email, user_name ].any? { |value| value.bytesize > 1024 }
      identifier(user_id)
    end

    def token3(nonce, user_email:, user_name:, user_id:, email_confirmed:, password:)
      Digest::MD5.hexdigest(nonce + user_email + user_name + user_id + email_confirmed + password)
    end

    def token(nonce, password:)
      Digest::MD5.hexdigest(nonce + password)
    end

    def token2(nonce, user_email:, user_name:, user_id:, password:)
      Digest::MD5.hexdigest(nonce + user_email + user_name + user_id + password)
    end

    def matches?(expected, supplied)
      supplied.is_a?(String) && supplied.match?(/\A[0-9a-f]{32}\z/) &&
        ActiveSupport::SecurityUtils.fixed_length_secure_compare(expected, supplied)
    end
  end
end
