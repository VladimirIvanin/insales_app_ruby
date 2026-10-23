class VerificationBudget < ApplicationRecord
  WINDOW = 1.minute
  LIMIT = 10
  CANDIDATE_COOLDOWN = 10.seconds
  MAX_CONCURRENT = 2

  def self.claim(candidate)
    transaction do
      current = InstallationCandidate.lock.find_by(id: candidate.id)
      next unless current && current.expires_at > Time.current
      next if current.last_checked_at && current.last_checked_at > CANDIDATE_COOLDOWN.ago
      VerificationPermit.where("expires_at <= ?", Time.current).delete_all
      next if VerificationPermit.count >= MAX_CONCURRENT
      budget = lock.find_or_create_by!(domain: current.domain) { |record| record.window_started_at = Time.current }
      if budget.window_started_at <= WINDOW.ago
        budget.assign_attributes(window_started_at: Time.current, attempts: 0)
      end
      next if budget.attempts >= LIMIT
      budget.update!(attempts: budget.attempts + 1)
      current.update!(last_checked_at: Time.current, verification_status: "checking")
      VerificationPermit.create!(expires_at: 6.seconds.from_now)
    end
  end
end
