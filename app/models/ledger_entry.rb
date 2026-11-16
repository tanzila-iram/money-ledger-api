class LedgerEntry < ApplicationRecord
  belongs_to :account,
             foreign_key: :user_id,
             primary_key: :user_id,
             inverse_of: :ledger_entries

  validates :user_id, presence: true

  validates :entry_type,
            inclusion: {
              in: %w[credit debit]
            }

  validates :amount,
            numericality: {
              only_integer: true,
              greater_than: 0
            }

  attr_readonly :user_id,
                :entry_type,
                :amount,
                :created_at
end