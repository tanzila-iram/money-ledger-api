
require "net/http"
require "json"
require "thread"

URL = URI("#{ENV.fetch('BENCHMARK_BASE_URL', 'http://localhost:8080')}/balance/bench_50000")
TOKEN = ENV.fetch("API_TOKEN", "recruitment-test-token")

REQUESTS = 1_000
WORKERS = Integer(ENV.fetch("BENCHMARK_WORKERS", "20"))
EXPECTED_BALANCE = 10_000

def percentile(sorted_values, percentage)
  index = (sorted_values.length - 1) * percentage / 100.0

  lower = index.floor
  upper = index.ceil
  fraction = index - lower

  sorted_values[lower] * (1 - fraction) +
    sorted_values[upper] * fraction
end

def make_request
  request = Net::HTTP::Get.new(URL)
  request["Authorization"] = "Bearer #{TOKEN}"

  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  success = false

  begin
    response = Net::HTTP.start(
      URL.host,
      URL.port,
      open_timeout: 5,
      read_timeout: 15
    ) do |http|
      http.request(request)
    end

    body = JSON.parse(response.body)

    success =
      response.code == "200" &&
      body["balance"] == EXPECTED_BALANCE
  rescue StandardError
    success = false
  end

  elapsed_ms =
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000

  [elapsed_ms, success]
end

puts "Running #{REQUESTS} requests with #{WORKERS} workers..."

queue = Queue.new
REQUESTS.times { |i| queue << i }

results = []
mutex = Mutex.new

started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

threads = WORKERS.times.map do
  Thread.new do
    loop do
      begin
        queue.pop(true)
      rescue ThreadError
        break
      end

      result = make_request

      mutex.synchronize do
        results << result
      end
    end
  end
end

threads.each(&:join)

duration =
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

latencies = results.map(&:first).sort
successes = results.count { |_, success| success }
failures = results.length - successes

average = latencies.sum / latencies.length

puts
puts "Successful requests: #{successes}/#{REQUESTS}"
puts "Failed requests: #{failures}"
puts "Total duration: #{duration.round(2)}s"
puts "Throughput: #{(REQUESTS / duration).round(2)} requests/sec"
puts "Average latency: #{average.round(2)} ms"
puts "p50 latency: #{percentile(latencies, 50).round(2)} ms"
puts "p95 latency: #{percentile(latencies, 95).round(2)} ms"
puts "p99 latency: #{percentile(latencies, 99).round(2)} ms"
