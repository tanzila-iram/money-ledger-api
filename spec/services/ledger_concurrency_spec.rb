
require "rails_helper"
require "securerandom"

RSpec.describe "Ledger concurrency", type: :service do
  # These examples use real database transactions across threads.
  # Disable the outer RSpec transaction so threads can share committed data.
  self.use_transactional_tests = false

  def run_concurrently(thread_count)
    ready = Queue.new
    start = Queue.new
    results = Queue.new

    threads = Array.new(thread_count) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop

          begin
            results << [:success, yield]
          rescue StandardError => e
            results << [:error, e]
          end
        end
      end
    end

    thread_count.times { ready.pop }
    thread_count.times { start << true }
    threads.each(&:join)

    thread_count.times.map { results.pop }
  end

  it "handles 1000 concurrent credits without losing money" do
    user_id = "credit_#{SecureRandom.hex(8)}"

    # 20 threads, each performing 50 credits.
    results = run_concurrently(20) do
      50.times do
        LedgerService.credit(user_id: user_id, amount: 100)
      end
    end

    errors = results.select { |status, _| status == :error }

    expect(errors).to be_empty
    expect(Account.find(user_id).balance).to eq(100_000)

    entries = LedgerEntry.where(user_id: user_id)

    expect(entries.count).to eq(1_000)
    expect(entries.sum(:amount)).to eq(100_000)
  end

  it "allows only one competing debit when funds cover one" do
    user_id = "debit_#{SecureRandom.hex(8)}"

    LedgerService.credit(user_id: user_id, amount: 100)

    results = run_concurrently(2) do
      LedgerService.debit(user_id: user_id, amount: 60)
    end

    successes = results.count { |status, _| status == :success }
    insufficient = results.count do |status, error|
      status == :error && error.is_a?(LedgerService::InsufficientFunds)
    end

    expect(successes).to eq(1)
    expect(insufficient).to eq(1)
    expect(Account.find(user_id).balance).to eq(40)

    entries = LedgerEntry.where(user_id: user_id)
    expect(entries.where(entry_type: "debit").count).to eq(1)

    credits = entries.where(entry_type: "credit").sum(:amount)
    debits = entries.where(entry_type: "debit").sum(:amount)

    expect(credits - debits).to eq(40)
  end
end
