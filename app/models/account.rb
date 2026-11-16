class Account < ApplicationRecord
  self.primary_key = "user_id"

  has_many :ledger_entries,
           foreign_key: :user_id,
           primary_key: :user_id,
           inverse_of: :account

  validates :user_id,
            presence: true,
            length: { maximum: 64 },
            format: {
              with: /\A[A-Za-z0-9_-]+\z/
            }

  validates :balance,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }
end