module Insales
  class CandidateVerification
    def initialize(client_factory:)
      @client_factory = client_factory
    end

    def check(candidate, timeout: 5)
      current = InstallationCandidate.find_by(id: candidate.id)
      return :unavailable unless current
      if current.last_checked_at && current.last_checked_at > VerificationBudget::CANDIDATE_COOLDOWN.ago
        return current.verification_status == "valid" ? :valid : :unavailable
      end
      permit = VerificationBudget.claim(current)
      return :unavailable unless permit
      status = request_account(current, timeout)
      InstallationCandidate.where(id: current.id).update_all(verification_status: status.to_s)
      status
    ensure
      permit&.destroy!
    end

    private
      def request_account(candidate, timeout)
        account = @client_factory.call(candidate.domain, candidate.api_password).account(timeout: timeout).data
        account.fetch("id") == candidate.insales_id ? :valid : :invalid
      rescue ApiError => error
        return :invalid if [ 401, 403 ].include?(error.status)
        VerificationBudget.pause(candidate.domain, error.retry_after)
        :unavailable
      rescue TransportError, ResourceError
        :unavailable
      end
  end
end
