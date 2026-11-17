# script/test_concurrent_credits.rb
require "securerandom"

user_id = "concurrent_credit_#{SecureRandom.hex(6)}"
thread_count = 20
credits_per_thread = 50
amount = 100

errors = Queue.new

threads = thread_count.times.map do
  Thread.new do
    begin
      ActiveRecord::Base.connection_pool.with_connection do
        credits_per_thread.times do
          LedgerService.credit(
            user_id: user_id,
            amount: amount
          )
        end
      end
    rescue StandardError => e
      errors << e
    end
  end
end

threads.each(&:join)

expected_balance = thread_count * credits_per_thread * amount

account = Account.find_by(user_id: user_id)
entries = LedgerEntry.where(user_id: user_id)

ledger_balance = entries.where(entry_type: "credit").sum(:amount) -
                 entries.where(entry_type: "debit").sum(:amount)

puts "Expected balance: #{expected_balance}"
puts "Actual balance: #{account&.balance}"
puts "Ledger balance: #{ledger_balance}"
puts "Ledger entries: #{entries.count}"
puts "Errors: #{errors.size}"

raise "Concurrency test failed" unless
  account&.balance == expected_balance &&
  ledger_balance == expected_balance &&
  entries.count == thread_count * credits_per_thread &&
  errors.empty?

puts "PASS: Concurrent credits are consistent"
