
require "net/http"
require "json"
require "thread"
require "securerandom"

BASE_URL = URI(ENV.fetch("BENCHMARK_BASE_URL", "http://localhost:8080"))
TOKEN = ENV.fetch("API_TOKEN", "recruitment-test-token")

WORKERS = Integer(ENV.fetch("BENCHMARK_WORKERS", "20"))
CREDITS = 100
DEBITS = 100

INITIAL_BALANCE = 1_000
CREDIT_AMOUNT = 10
DEBIT_AMOUNT = 5

# Unique account prevents conflicts with previous benchmark runs.
USER_ID = "concurrency_#{SecureRandom.hex(6)}"

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

  elapsed_ms =
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000

  [response.code.to_i, JSON.parse(response.body), elapsed_ms]
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

puts "Creating test account: #{USER_ID}"

status, body, = api_request(
  :post,
  "/credit",
  { user_id: USER_ID, amount: INITIAL_BALANCE }
)

abort "Account setup failed: #{body}" unless status == 200

jobs = []

CREDITS.times do
  jobs << [:credit, CREDIT_AMOUNT]
end

DEBITS.times do
  jobs << [:debit, DEBIT_AMOUNT]
end

jobs.shuffle!

queue = Queue.new
jobs.each { |job| queue << job }

results = []
mutex = Mutex.new

puts "Running #{jobs.length} transactions with #{WORKERS} workers..."

started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

threads = WORKERS.times.map do
  Thread.new do
    loop do
      job = begin
        queue.pop(true)
      rescue ThreadError
        break
      end

      operation, amount = job

      begin
        status, body, latency = api_request(
          :post,
          "/#{operation}",
          { user_id: USER_ID, amount: amount }
        )

        mutex.synchronize do
          results << {
            operation: operation,
            status: status,
            body: body,
            latency: latency
          }
        end
      rescue StandardError => e
        mutex.synchronize do
          results << {
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
  (CREDITS * CREDIT_AMOUNT) -
  (DEBITS * DEBIT_AMOUNT)

status, body, = api_request(:get, "/balance/#{USER_ID}")

actual_balance = body["balance"]

latencies = results.filter_map { |result| result[:latency] }

puts
puts "========== CONCURRENCY RESULTS =========="
puts "User ID: #{USER_ID}"
puts "Total transactions: #{jobs.length}"
puts "Successful transactions: #{successful}"
puts "Failed transactions: #{failed.length}"
puts "Duration: #{duration.round(2)}s"
puts "Throughput: #{(jobs.length / duration).round(2)} transactions/sec"

unless latencies.empty?
  puts "p50 latency: #{percentile(latencies, 50).round(2)} ms"
  puts "p95 latency: #{percentile(latencies, 95).round(2)} ms"
  puts "p99 latency: #{percentile(latencies, 99).round(2)} ms"
end

puts
puts "Expected balance: #{expected_balance}"
puts "Actual balance: #{actual_balance}"

if failed.any?
  puts
  puts "Failure details:"
  failed.first(5).each { |failure| p failure }
end

if successful == jobs.length &&
   status == 200 &&
   actual_balance == expected_balance
  puts
  puts "PASS: All concurrent transactions completed correctly."
else
  puts
  puts "FAIL: Concurrent transaction test failed."
  exit 1
end
