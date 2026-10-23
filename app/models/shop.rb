class Shop < ApplicationRecord
  encrypts :api_password
  has_many :installation_candidates, foreign_key: :insales_id, primary_key: :insales_id, dependent: :delete_all
  has_many :login_challenges, dependent: :delete_all
  has_many :app_sessions, dependent: :delete_all
  has_many :revoked_credentials, foreign_key: :insales_id, primary_key: :insales_id, dependent: :delete_all

  def active?
    api_password.present?
  end

  def revoke_sessions!
    app_sessions.delete_all
    login_challenges.delete_all
  end
end
