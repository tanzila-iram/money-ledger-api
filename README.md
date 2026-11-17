# Money Ledger API

A concurrent money ledger API built with **Ruby on Rails 8.1** and **PostgreSQL 16**.

The API manages balances for multiple users through three operations: credit, debit, and balance retrieval. It is designed to maintain data consistency under concurrent requests and support efficient balance lookups with millions of ledger entries.

## 1. Quick Start

### Requirements

- Docker
- Docker Compose

No separate Ruby or PostgreSQL installation is required.

### Start the application

From the project root, run:

```bash
docker compose up
```

Docker Compose builds the application image if needed, starts PostgreSQL, waits for the database health check, prepares the database, and starts the Rails API.

**API URL:** `http://localhost:8080`

### Authentication

All endpoints require a static bearer token.

Default token:

```text
Authorization: Bearer recruitment-test-token
```

To override the token:

```bash
API_TOKEN=your-custom-token docker compose up
```

Missing or invalid authentication returns HTTP `401 Unauthorized`.

## 2. API Endpoints

### Credit

`POST /credit`

Creates an account if it does not exist and adds the requested amount to its balance.

```bash
curl -i -X POST http://localhost:8080/credit \
  -H "Authorization: Bearer recruitment-test-token" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"demo_user","amount":1000}'
```

**Response — HTTP 200**

```json
{
  "user_id": "demo_user",
  "balance": 1000
}
```

### Debit

`POST /debit`

Deducts the requested amount only if the account exists and has sufficient funds.

```bash
curl -i -X POST http://localhost:8080/debit \
  -H "Authorization: Bearer recruitment-test-token" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"demo_user","amount":300}'
```

**Response — HTTP 200**

```json
{
  "user_id": "demo_user",
  "balance": 700
}
```

### Get Balance

`GET /balance/:user_id`

Returns the current balance of an existing account.

```bash
curl -i \
  -H "Authorization: Bearer recruitment-test-token" \
  http://localhost:8080/balance/demo_user
```

**Response — HTTP 200**

```json
{
  "user_id": "demo_user",
  "balance": 700
}
```

The examples assume `demo_user` does not already exist. Repeating a credit or debit request changes the balance again.

### Input Validation

| Field | Rule |
|---|---|
| `user_id` | 1–64 ASCII letters, digits, underscores, or hyphens |
| `amount` | JSON integer between 1 and 1,000,000,000 |
| Additional JSON fields | Ignored |

### Error Responses

| HTTP Status | Error | Description |
|---|---|---|
| 400 | `invalid_request` | Invalid input or request body |
| 401 | `unauthorized` | Missing or invalid bearer token |
| 404 | `user_not_found` | Account does not exist |
| 409 | `insufficient_funds` | Insufficient balance for debit |
| 409 | `balance_overflow` | Credit exceeds supported balance range |

Example missing-account response:

```json
{
  "error": "user_not_found",
  "message": "User not found"
}
```

## 3. Database Design and Concurrency

The application uses two primary PostgreSQL tables.

### Accounts

Stores the current balance for each user.

| Column | Purpose |
|---|---|
| `user_id` | Primary key |
| `balance` | Current balance stored as BIGINT |

A database constraint prevents negative balances.

### Ledger Entries

Stores successful balance-changing operations.

| Column | Purpose |
|---|---|
| `id` | BIGINT primary key |
| `user_id` | Account reference |
| `entry_type` | Credit or debit |
| `amount` | Transaction amount |
| `created_at` | Creation timestamp |

A PostgreSQL trigger prevents existing ledger entries from being updated or deleted, enforcing an append-only transaction history.

### Atomic Credits

Credits use PostgreSQL UPSERT to create an account or increase its balance atomically.

An overflow guard prevents the balance from exceeding the supported BIGINT range.

### Atomic Debits

Debits use a conditional SQL UPDATE that modifies the balance only when sufficient funds exist.

This prevents concurrent debit requests from overspending the same account.

### Transaction Consistency

Each successful balance modification and its corresponding ledger entry insertion occur within a single PostgreSQL transaction.

If either operation fails, the transaction rolls back.

This design provides:

- No lost balance updates under concurrent requests.
- No negative account balances.
- Atomic balance and ledger changes.
- Serialization of conflicting writes to the same account.
- Independent concurrency across different accounts.

### Efficient Balance Retrieval

The current balance is stored directly in `accounts`, avoiding the need to aggregate the transaction ledger on every request.

Balance retrieval uses the indexed `user_id` primary key.

## 4. Automated Tests

The project uses RSpec for request, model, service, and concurrency testing.

With Docker Compose running, execute:

```bash
docker compose exec \
  -e RAILS_ENV=test \
  -e DB_POOL=25 \
  -e API_TOKEN=recruitment-test-token \
  api bundle exec rspec
```

**Verified result:**

```text
30 examples, 0 failures
```

Tests cover:

- Bearer-token authentication.
- Input validation and error responses.
- Account creation and credit operations.
- Successful debits and insufficient funds.
- Existing and nonexistent account balances.
- Transaction rollback consistency.
- Concurrent balance modifications.
- Ledger immutability.
- Balance overflow protection.

## 5. Large-Scale Benchmark Setup

The project includes `db/benchmark_seed.rb`, which generates:

- **100,000 accounts**
- **10,000,000 ledger entries**

The seed uses PostgreSQL bulk insertion and `generate_series` for efficient data generation.

**Run the seed only against a disposable benchmark database.** It refuses to run in the Rails production environment and aborts if benchmark accounts already exist.

### Prepare the benchmark database

With Docker Compose running:

```bash
docker compose exec \
  -e RAILS_ENV=development \
  api bin/rails db:prepare
```

Seed the development database:

```bash
docker compose exec \
  -e RAILS_ENV=development \
  api bin/rails runner db/benchmark_seed.rb
```

The benchmark data is stored in `money_ledger_development`, separate from the normal API's `money_ledger_production` database.

### Start the benchmark API

To reproduce production-mode HTTP benchmarks against the large dataset, start a separate API instance on port 8081.

Ensure port 8081 is available, then run:

```bash
docker compose run --rm \
  -p 8081:8080 \
  -e RAILS_ENV=production \
  -e DATABASE_URL=postgresql://ledger:ledger_password@db:5432/money_ledger_development \
  api bin/rails server -b 0.0.0.0 -p 8080
```

This starts Rails in production mode while connecting to the seeded benchmark database. The normal API remains available on port 8080.

The database credentials in this command are the local Docker Compose development credentials, not production secrets.

### Run the benchmarks

From the project root, in another terminal:

**Balance retrieval**

```bash
BENCHMARK_WORKERS=100 \
BENCHMARK_BASE_URL=http://localhost:8081 \
ruby script/benchmark.rb
```

**Concurrent transactions on one account**

```bash
BENCHMARK_WORKERS=100 \
BENCHMARK_BASE_URL=http://localhost:8081 \
ruby script/concurrency_benchmark.rb
```

**Concurrent transactions across multiple accounts**

```bash
BENCHMARK_WORKERS=100 \
BENCHMARK_BASE_URL=http://localhost:8081 \
ruby script/multi_account_benchmark.rb
```

The scripts report throughput and latency percentiles and verify balance consistency where applicable.

## 6. Performance Results

Benchmarks were executed locally using:

- Rails 8.1 in production mode.
- PostgreSQL 16.
- 100 concurrent HTTP clients.
- Five Rails server threads.
- A database containing more than 100,000 accounts and 10 million ledger entries.

### HTTP Benchmark Results

| Benchmark | Requests | Successful | Throughput | p50 | p95 | p99 |
|---|---:|---:|---:|---:|---:|---:|
| Balance retrieval | 1,000 | 1,000 | 171.76 req/s | 547.38 ms | 727.97 ms | 795.45 ms |
| Same-account transactions | 200 | 200 | 77.06 tx/s | 1,195.09 ms | 1,287.71 ms | 1,395.93 ms |
| Multi-account transactions | 1,000 | 1,000 | 91.49 tx/s | 1,067.13 ms | 1,172.45 ms | 1,198.65 ms |

### Consistency Verification

| Check | Result |
|---|---|
| Same-account expected balance | 1,500 |
| Same-account actual balance | 1,500 |
| Multi-account expected balance per account | 1,025 |
| Correct multi-account balances | 100/100 |
| Failed benchmark requests | 0 |

All three 100-client benchmark runs passed.

These measurements were collected locally. Actual p50 and p99 latencies may differ on the reviewer's machine.

## 7. Query Plan

Balance retrieval reads the current balance directly from the `accounts` table using its primary key.

The following query was tested against a database containing more than 100,000 accounts and 10 million ledger entries:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT balance FROM accounts WHERE user_id = 'bench_1';
```

Observed PostgreSQL query plan:

```text
Index Scan using accounts_pkey on accounts
  Index Cond: (user_id = 'bench_1')
  Buffers: shared hit=4
Planning Time: 0.724 ms
Execution Time: 0.183 ms
```

PostgreSQL uses the primary-key index instead of scanning all accounts or aggregating the ledger.

The reported execution time measures the database query only, not the complete HTTP request.

## 8. Design Decisions and Trade-offs

### Materialized Account Balances

Storing the current balance in `accounts` enables efficient balance retrieval.

**Trade-off:** Each successful transaction must update the account balance and append a ledger entry atomically.

### Database-Level Concurrency Control

PostgreSQL atomic operations and row-level locking prevent lost updates and overspending.

**Trade-off:** Concurrent requests modifying the same account must wait for conflicting transactions.

### Append-Only Ledger

A database trigger prevents modification or deletion of historical ledger entries.

**Trade-off:** Ledger storage grows continuously as transactions accumulate.

### Single Transactional Database

PostgreSQL stores both account balances and ledger entries, allowing atomic updates without distributed transactions.

**Trade-off:** Database capacity and write contention must be managed as the system scales.

## 9. Known Limits and Future Improvements

- **Idempotency:** Credit and debit operations do not currently support idempotency keys. Retrying a successful request may apply the transaction again.
- **Write contention:** Concurrent updates to the same account are serialized, increasing latency under heavy contention.
- **Ledger growth:** The append-only ledger grows continuously and may eventually benefit from partitioning.
- **Load testing:** Results depend on the local environment and should be remeasured under the reviewer's hardware and workload.

With more time, I would prioritize idempotency keys, broader load testing, production monitoring, and long-term ledger partitioning.

---

**Developed and tested by Tanzila.**