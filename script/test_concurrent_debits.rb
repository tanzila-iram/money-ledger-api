# script/test_concurrent_debits.rb

require "securerandom"

user_id = "concurrent_debit_#{SecureRandom.hex(6)}"

# Start with a balance of 100
LedgerService.credit(user_id: user_id, amount: 100)

results = Queue.new

threads = 2.times.map do
  Thread.new do
    begin
      ActiveRecord::Base.connection_pool.with_connection do
        balance = LedgerService.debit(
          user_id: user_id,
          amount: 60
        )

        results << [:success, balance]
      end
    rescue LedgerService::InsufficientFunds
      results << [:insufficient_funds, nil]
    rescue StandardError => e
      results << [:error, e.class.name]
    end
  end
end

threads.each(&:join)

outcomes = 2.times.map { results.pop }

account = Account.find(user_id)
entries = LedgerEntry.where(user_id: user_id)

successes = outcomes.count { |status, _| status == :success }
insufficient = outcomes.count { |status, _| status == :insufficient_funds }

credits = entries.where(entry_type: "credit").sum(:amount)
debits = entries.where(entry_type: "debit").sum(:amount)

puts "Results: #{outcomes.inspect}"
puts "Successful debits: #{successes}"
puts "Insufficient funds: #{insufficient}"
puts "Final balance: #{account.balance}"
puts "Ledger balance: #{credits - debits}"
puts "Debit entries: #{entries.where(entry_type: 'debit').count}"

raise "Concurrent debit test failed" unless
  successes == 1 &&
  insufficient == 1 &&
  account.balance == 40 &&
  credits - debits == 40 &&
  entries.where(entry_type: "debit").count == 1

puts "PASS: Concurrent debits are consistent"