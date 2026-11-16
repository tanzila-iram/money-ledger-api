class LedgerService
  class UserNotFound < StandardError; end
  class InsufficientFunds < StandardError; end
  class BalanceOverflow < StandardError; end

  class << self

    def credit(user_id:, amount:)
        Account.transaction do
            result = ActiveRecord::Base.connection.exec_query(
            <<~SQL,
                INSERT INTO accounts (user_id, balance)
                VALUES ($1, $2)
                ON CONFLICT (user_id)
                DO UPDATE SET balance = accounts.balance + EXCLUDED.balance
                WHERE accounts.balance <= 9223372036854775807 - EXCLUDED.balance
                RETURNING balance
            SQL
            "Credit",
            [
                bind("user_id", user_id),
                bind("amount", amount)
            ]
            )

            raise BalanceOverflow if result.rows.empty?

            LedgerEntry.create!(
            user_id: user_id,
            entry_type: "credit",
            amount: amount
            )

            result.rows.first.first.to_i
        end
    end


    def debit(user_id:, amount:)
      Account.transaction do
        connection = ActiveRecord::Base.connection

        result = connection.exec_query(
          <<~SQL,
            UPDATE accounts
            SET balance = balance - $1
            WHERE user_id = $2
              AND balance >= $1
            RETURNING balance
          SQL
          "Debit",
          [
            bind("amount", amount),
            bind("user_id", user_id)
          ]
        )

        if result.rows.empty?
          raise UserNotFound unless Account.exists?(user_id: user_id)

          raise InsufficientFunds
        end

        LedgerEntry.create!(
          user_id: user_id,
          entry_type: "debit",
          amount: amount
        )

        result.rows.first.first.to_i
      end
    end

    private

    def bind(name, value)
      ActiveRecord::Relation::QueryAttribute.new(
        name,
        value,
        value.is_a?(Integer) ?
          ActiveRecord::Type::Integer.new :
          ActiveRecord::Type::String.new
      )
    end
  end
end