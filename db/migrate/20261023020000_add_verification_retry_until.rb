class AddVerificationRetryUntil < ActiveRecord::Migration[8.1]
  def change
    add_column :verification_budgets, :retry_until, :datetime
  end
end
