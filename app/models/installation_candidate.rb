class InstallationCandidate < ApplicationRecord
  belongs_to :shop, foreign_key: :insales_id, primary_key: :insales_id, optional: true
  encrypts :api_password
  scope :unexpired, -> { where("expires_at > ?", Time.current) }
end
