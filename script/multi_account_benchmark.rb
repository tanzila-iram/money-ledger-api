
require "net/http"
require "json"
require "thread"
require "securerandom"

BASE_URL = URI(ENV.fetch("BENCHMARK_BASE_URL", "http://localhost:8080"))
TOKEN = ENV.fetch("API_TOKEN", "recruitment-test-token")

WORKERS = Integer(ENV.fetch("BENCHMARK_WORKERS", "20"))
CREDITS_PER_ACCOUNT = 5
DEBITS_PER_ACCOUNT = 5

INITIAL_BALANCE = 1_000
CREDIT_AMOUNT = 10
DEBIT_AMOUNT = 5

RUN_ID = SecureRandom.hex(6)

def api_request(method, path, payload = nil)
  uri = URI.join(BASE_URL.to_s, path)

  request =
    if method == :post
      Net::HTTP::Post.new(uri)
    else
      Net::HTTP::Get.new(uri)
    end

  request["Authorization"] = "Bearer #{TOKEN}"

  if payload
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload)
  end

  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  response = Net::HTTP.start(
    uri.host,
    uri.port,
    open_timeout: 5,
    read_timeout: 30
  ) do |http|
    http.request(request)
  end

  latency_ms =
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000

  [response.code.to_i, JSON.parse(response.body), latency_ms]
end

def percentile(values, percentage)
  sorted = values.sort
  index = (sorted.length - 1) * percentage / 100.0

  lower = index.floor
  upper = index.ceil
  fraction = index - lower

  sorted[lower] * (1 - fraction) +
    sorted[upper] * fraction
end

puts "Creating #{WORKERS} test accounts..."

accounts = WORKERS.times.map do |index|
  "multi_#{RUN_ID}_#{index}"
end

accounts.each do |user_id|
  status, body, = api_request(
    :post,
    "/credit",
    { user_id: user_id, amount: INITIAL_BALANCE }
  )

  abort "Account setup failed: #{user_id}: #{body}" unless status == 200
end

puts "All accounts created successfully."

# Each worker receives its own account.
# No two workers modify the same account.

results = []
mutex = Mutex.new

total_transactions =
  WORKERS * (CREDITS_PER_ACCOUNT + DEBITS_PER_ACCOUNT)

puts "Running #{total_transactions} transactions with #{WORKERS} workers..."

started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

threads = accounts.map do |user_id|
  Thread.new do
    jobs = []

    CREDITS_PER_ACCOUNT.times do
      jobs << [:credit, CREDIT_AMOUNT]
    end

    DEBITS_PER_ACCOUNT.times do
      jobs << [:debit, DEBIT_AMOUNT]
    end

    jobs.shuffle!

    jobs.each do |operation, amount|
      begin
        status, body, latency = api_request(
          :post,
          "/#{operation}",
          { user_id: user_id, amount: amount }
        )

        mutex.synchronize do
          results << {
            user_id: user_id,
            operation: operation,
            status: status,
            body: body,
            latency: latency
          }
        end
      rescue StandardError => e
        mutex.synchronize do
          results << {
            user_id: user_id,
            operation: operation,
            status: nil,
            error: e.message,
            latency: nil
          }
        end
      end
    end
  end
end

threads.each(&:join)

duration =
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

successful = results.count { |result| result[:status] == 200 }
failed = results.reject { |result| result[:status] == 200 }

expected_balance =
  INITIAL_BALANCE +
  (CREDITS_PER_ACCOUNT * CREDIT_AMOUNT) -
  (DEBITS_PER_ACCOUNT * DEBIT_AMOUNT)

latencies = results.filter_map { |result| result[:latency] }

puts
puts "========== MULTI-ACCOUNT RESULTS =========="
puts "Accounts: #{WORKERS}"
puts "Total transactions: #{total_transactions}"
puts "Successful transactions: #{successful}"
puts "Failed transactions: #{failed.length}"
puts "Duration: #{duration.round(2)}s"
puts "Throughput: #{(total_transactions / duration).round(2)} transactions/sec"

unless latencies.empty?
  puts "p50 latency: #{percentile(latencies, 50).round(2)} ms"
  puts "p95 latency: #{percentile(latencies, 95).round(2)} ms"
  puts "p99 latency: #{percentile(latencies, 99).round(2)} ms"
end

puts
puts "Verifying account balances..."

balance_failures = []

accounts.each do |user_id|
  status, body, = api_request(:get, "/balance/#{user_id}")

  if status != 200 || body["balance"] != expected_balance
    balance_failures << {
      user_id: user_id,
      status: status,
      actual_balance: body["balance"]
    }
  end
end

puts "Expected balance per account: #{expected_balance}"
puts "Correct account balances: #{WORKERS - balance_failures.length}/#{WORKERS}"

if failed.any?
  puts
  puts "Transaction failures:"
  failed.first(5).each { |failure| p failure }
end

if balance_failures.any?
  puts
  puts "Balance mismatches:"
  balance_failures.first(5).each { |failure| p failure }
end

if successful == total_transactions && balance_failures.empty?
  puts
  puts "PASS: All concurrent transactions completed correctly."
else
  puts
  puts "FAIL: Multi-account concurrency test failed."
  exit 1
end

puts
puts "Run ID: #{RUN_ID}"
