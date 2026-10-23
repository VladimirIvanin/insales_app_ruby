class AppSession < ApplicationRecord
  belongs_to :shop
  IDLE_TIMEOUT = 30.minutes
  ABSOLUTE_TIMEOUT = 1.hour
end
