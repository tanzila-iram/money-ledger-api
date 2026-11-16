class CreateLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :ledger_entries do |t|
      t.string :user_id, null: false, limit: 64
      t.string :entry_type, null: false, limit: 6
      t.bigint :amount, null: false

      t.datetime :created_at,
        null: false,
        default: -> { "CURRENT_TIMESTAMP" }
    end

    add_foreign_key :ledger_entries,
      :accounts,
      column: :user_id,
      primary_key: :user_id

    add_index :ledger_entries, :user_id

    add_check_constraint :ledger_entries,
      "amount > 0",
      name: "ledger_amount_positive"

    add_check_constraint :ledger_entries,
      "entry_type IN ('credit', 'debit')",
      name: "ledger_entry_type_valid"
  end
end