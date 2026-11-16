class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts, id: false do |t|
      t.string :user_id, limit: 64, primary_key: true
      t.bigint :balance, null: false, default: 0
    end

    add_check_constraint :accounts,
      "balance >= 0",
      name: "accounts_balance_non_negative"

    add_check_constraint :accounts,
      "user_id ~ '^[A-Za-z0-9_-]{1,64}$'",
      name: "accounts_user_id_format"
  end
end