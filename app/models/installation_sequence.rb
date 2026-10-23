class InstallationSequence < ApplicationRecord
  def self.next_candidate_id
    transaction do
      sequence = lock.find_or_create_by!(id: 1)
      sequence.update!(last_value: sequence.last_value + 1)
      sequence.last_value
    end
  end
end
