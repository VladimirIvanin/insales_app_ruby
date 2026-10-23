module Insales
  class Sessions
    def initialize(settings:)
      @settings = settings
    end

    def authenticate(token)
      return if token.blank?
      Shop.transaction do
        record = AppSession.lock.find_by(token_digest: Digest::SHA256.hexdigest(token))
        next unless record
        store = Shop.lock.find(record.shop_id)
        unless @settings.allowed_shops.include?(store.domain)
          store.revoke_sessions!
          next
        end
        if record.expires_at <= Time.current || record.last_seen_at <= AppSession::IDLE_TIMEOUT.ago ||
            !store.active? || record.generation != store.generation
          record.destroy!
          next
        end
        record.update!(last_seen_at: Time.current) if record.last_seen_at <= 1.minute.ago
        Lifecycle::Context.new(session: record, shop: store)
      end
    end
  end
end
