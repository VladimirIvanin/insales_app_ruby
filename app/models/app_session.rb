class AppSession < ApplicationRecord
  belongs_to :shop
  alias_attribute :callback_user_id, :user_id
  IDLE_TIMEOUT = 30.minutes
  ABSOLUTE_TIMEOUT = 1.hour
end
