module Insales
  class Uninstalls
    def call(domain:, id:, token:)
      raise Protocol::InvalidInput, "Invalid credential" unless token.match?(/\A[0-9a-f]{32}\z/)
      digest = Digest::SHA256.hexdigest(token)
      Shop.transaction do
        identity = { domain: domain, insales_id: id, credential_digest: digest }
        store = Shop.lock.find_by(insales_id: id, domain: domain)
        matching = InstallationCandidate.where(**identity)
        active_matches = store&.active? && Protocol.matches?(store.api_password, token)
        known = RevokedCredential.exists?(**identity)
        raise Lifecycle::Failure.new(:invalid_credential, 403) unless active_matches || matching.exists? || known
        if active_matches
          store.revoke_sessions!
          store.update!(api_password: nil, credential_digest: nil)
        end
        matching.delete_all
        RevokedCredential.find_or_create_by!(**identity)
      end
    end
  end
end
