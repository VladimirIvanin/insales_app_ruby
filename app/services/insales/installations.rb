module Insales
  class Installations
    Admission = Data.define(:status, :backlog)

    def initialize(settings:, client_factory:)
      @settings = settings
      @verification = CandidateVerification.new(client_factory: client_factory)
    end

    def install(domain:, id:, token:)
      raise Protocol::InvalidInput, "Invalid installation token" if token.empty? || token.bytesize > 1024
      password = Protocol.password(token, @settings.app_secret)
      attributes = { domain: domain, id: id, password: password, digest: Digest::SHA256.hexdigest(password) }
      admission = admit(**attributes)
      return unless admission.status == :full
      rejected = find_invalid_candidate(admission.backlog)
      raise Lifecycle::Failure.new(:install_limit, 503) unless rejected
      if admit(**attributes, rejected_candidate_id: rejected.id).status == :full
        raise Lifecycle::Failure.new(:install_limit, 503)
      end
    end

    def verify_and_activate(domain, id)
      store = Shop.find_by(insales_id: id)
      candidate = InstallationCandidate.unexpired.where(domain: domain, insales_id: id)
        .where("id > ?", store&.generation || 0).order(id: :desc).first
      return :absent unless candidate
      status = @verification.check(candidate)
      case status
      when :valid then activate(candidate.id)
      when :invalid then candidate.destroy!
      end
      status
    end

    private
      def admit(domain:, id:, password:, digest:, rejected_candidate_id: nil)
        InstallationCandidate.transaction do
          identity = { domain: domain, insales_id: id, credential_digest: digest }
          if RevokedCredential.exists?(**identity) || Shop.exists?(**identity) || InstallationCandidate.unexpired.exists?(**identity)
            next Admission.new(status: :duplicate, backlog: [])
          end
          InstallationCandidate.where(domain: domain).where("expires_at <= ?", Time.current).delete_all
          InstallationCandidate.where(domain: domain, id: rejected_candidate_id).delete_all if rejected_candidate_id
          backlog = InstallationCandidate.where(domain: domain).order(:id).limit(Lifecycle::CANDIDATE_LIMIT).to_a
          if backlog.size >= Lifecycle::CANDIDATE_LIMIT
            next Admission.new(status: :full, backlog: backlog)
          end
          InstallationCandidate.create!(**identity, id: InstallationSequence.next_candidate_id,
            api_password: password, expires_at: Lifecycle::CANDIDATE_TTL.from_now)
          Admission.new(status: :saved, backlog: [])
        end
      end

      def find_invalid_candidate(candidates)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Lifecycle::ADMISSION_TIMEOUT
        candidates.each do |candidate|
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break unless remaining.positive?
          status = @verification.check(candidate, timeout: remaining)
          return candidate if status == :invalid
          break if status == :unavailable
        end
        nil
      end

      def activate(candidate_id)
        Shop.transaction do
          candidate = InstallationCandidate.unexpired.lock.find_by(id: candidate_id)
          next unless candidate
          store = Shop.lock.find_or_create_by!(insales_id: candidate.insales_id)
          next if candidate.id <= store.generation
          former_owner = Shop.lock.where(domain: candidate.domain).where.not(id: store.id).first
          next if former_owner && former_owner.generation >= candidate.id
          retire(former_owner) if former_owner
          retire(store) if store.active?
          store.revoke_sessions!
          store.update!(domain: candidate.domain, generation: candidate.id,
            api_password: candidate.api_password, credential_digest: candidate.credential_digest)
          candidate.destroy!
        end
      end

      def retire(store)
        RevokedCredential.find_or_create_by!(insales_id: store.insales_id, domain: store.domain,
          credential_digest: store.credential_digest) if store.active?
        store.revoke_sessions!
        store.update!(domain: nil, api_password: nil, credential_digest: nil)
      end
  end
end
