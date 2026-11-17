# Generates 100,000 accounts and 10 million ledger entries
# for performance testing.
#
# Run only against a disposable development/benchmark database.


if Rails.env.production?
  abort "Benchmark seed cannot run in production"
end

if Account.where("user_id LIKE 'bench_%'").exists?
  abort "Benchmark accounts already exist. Seed aborted."
end

connection = ActiveRecord::Base.connection

account_count = 100_000
entries_per_account = 100
amount = 100
batch_size = 1_000


puts "Starting benchmark seed..."
puts "Accounts: #{account_count}"
puts "Entries: #{account_count * entries_per_account}"

started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

(1..account_count).each_slice(batch_size) do |account_ids|
  first_id = account_ids.first
  last_id = account_ids.last

  connection.transaction do
    connection.execute(<<~SQL)
      INSERT INTO accounts (user_id, balance)
      SELECT
        'bench_' || id,
        #{entries_per_account * amount}
      FROM generate_series(#{first_id}, #{last_id}) AS id;
    SQL

    connection.execute(<<~SQL)
      INSERT INTO ledger_entries
        (user_id, entry_type, amount, created_at)
      SELECT
        'bench_' || account_id,
        'credit',
        #{amount},
        NOW()
      FROM generate_series(#{first_id}, #{last_id}) AS account_id
      CROSS JOIN generate_series(1, #{entries_per_account}) AS entry_number;
    SQL
  end

  if last_id % 10_000 == 0
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    puts "Seeded #{last_id} accounts in #{elapsed.round(2)}s"
  end
end

elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

puts "Completed in #{elapsed.round(2)} seconds"
