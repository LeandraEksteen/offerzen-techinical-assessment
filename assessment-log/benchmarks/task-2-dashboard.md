# Task 2 dashboard: benchmark method and baseline

Measured before any improvement (TKT-4). Later tickets (TKT-5 to TKT-8) add one row each to the results table and keep the method unchanged. No claim in the docs goes without a number from here.

## Conditions (all runs)

- **Environment:** local development, not production. Development reloads code and does not cache views, so absolute numbers are not production numbers; the comparison that matters is before against after, on this same machine.
- **Machine:** Apple M1 Pro, 10 cores, 16 GB RAM, macOS 26.0.1. Ruby 3.3.3, Rails 8.1.4.1, PostgreSQL 16.9 (Homebrew, default settings, warm cache).
- **Data:** the seeded development database: 500,000 assessments, 20 companies. Company 01 holds 200,000 assessments and 20,000 employees; Company 02 holds 15,790 assessments and 1,579 employees (about one employee per ten assessments, a yearly assessment over ten years). Synthetic data only.
- **Switches:** diagnosis tools and log writing are off while timing: `BULLET=off MINI_PROFILER=off RAILS_LOG_LEVEL=warn`.
- **Method:** one warm-up, then the median of 5 runs, except the largest scenario (one run, 10-minute limit). A scenario that exceeds its limit is recorded as "did not finish".
- **Dashboard under test:** the baseline in TKT-4: every matching assessment loaded and rendered at once (no pagination), and each row reads its employee through the association (an N+1).

## How to repeat

```bash
BULLET=off MINI_PROFILER=off RAILS_LOG_LEVEL=warn bin/rails benchmark:dashboard                 # all three scenarios
BULLET=off MINI_PROFILER=off RAILS_LOG_LEVEL=warn SCENARIOS=normal,company2 bin/rails benchmark:dashboard
SCENARIO=big bin/rails benchmark:explain                                                        # EXPLAIN (ANALYZE, BUFFERS)
VIEW=default bin/rails dashboard:snapshot > /tmp/page1.txt                                      # then diff against the baseline snapshot
```

Load test (simple, `ab` is already on the machine; `hey` and `k6` are not): sign in with `curl`, then
`ab -n 20 -c 1 -H "Cookie: <session cookie>" -H "User-Agent: <browser UA>" "http://127.0.0.1:3055/dashboard?from=2024-01-01&to=2024-12-31"` against a server started with the same three switches.

## Baseline results (2026-11-07)

| Scenario | Rows | SQL queries run | Query-cache hits | Median ms (min-max) | HTML size | Result |
|---|---|---|---|---|---|---|
| Normal user: Company 02, assessment dates in 2024 | 1,516 | 1,414 | 105 | 421 (390-442) | 284 KB | HTTP 200 |
| Company 02, all rows | 15,790 | 14,787 | 1,006 | 3,921 (3,795-4,057) | 2,936 KB | HTTP 200 |
| Company 01 (largest), all rows | 200,000 | 199,064 | 940 | 58,019 (one run) | 37,287 KB | HTTP 200; peak memory 2.09 GB |

The number of SQL queries is almost exactly the number of rows: that is the N+1. "Query-cache hits" are repeated employee lookups that Rails' per-request cache answered without going to the database; they stay small because a company has many different employees.

### Load test (`ab`, normal-user page, 20 requests)

| Concurrency | Requests per second | Mean per request | 50% | 95% | Failed |
|---|---|---|---|---|---|
| 1 | 2.44 | 410 ms | 409 ms | 462 ms | 0 |
| 3 | 2.98 | 1,006 ms | 984 ms | 1,041 ms | 0 |

Three simultaneous users already triple the wait for each of them: the server (3 threads) is CPU-bound rendering these pages, so extra concurrency only queues requests.

### EXPLAIN (ANALYZE, BUFFERS) of the main query

Full output: `dashboard-explain-baseline.txt`.

| Scenario | Plan | Execution time |
|---|---|---|
| Normal user (1,516 rows) | Parallel sequential scan of `assessments`, sort, gather merge; reads about 33,000 buffers | 44.6 ms |
| Company 02, all rows | Parallel sequential scan, sort | 43.9 ms |
| Company 01, all rows | Parallel sequential scan, external merge sort on disk (about 100 MB temp) | 153.5 ms |

One employee lookup (what the N+1 repeats per row) is a primary-key index scan taking 0.012 to 0.016 ms.

### Diagnosis tools

- **Bullet** reports on the first request: `USE eager loading detected: Assessment => [:employee]`, "Add to your query: .includes([:employee])", pointing at the dashboard view line that reads the employee. Its log contains class and association names only, no data.
- **rack-mini-profiler** injects its badge into the page and records every request (the normal-user request took 1,292 ms with it on, against 421 ms with it off, which is why it is off while timing).

## What the numbers say

1. **The database query is not the problem.** The main query takes 44 to 153 ms in every scenario; the page takes 0.4 s, 3.9 s or 58 s. Almost all of the time is spent in Ruby: building one object per row, running one employee query per row, and rendering the table.
2. **An index would help only the 44 ms part.** The planned `(company_id, assessment_date)` index (TKT-7) replaces the sequential scan and the sort, so it saves tens of milliseconds, not seconds. Pagination (TKT-5) and eager loading (TKT-6) attack the real cost.
3. **The largest company's page is unusable as built:** a minute of server time, 199,064 queries, a 37 MB page and 2 GB of memory for one request.

## Results after each change (to be filled in by the tickets that follow)

| Change | Ticket | Normal user (ms) | Company 02 all (ms) | Company 01 all (ms) | Queries (normal user) | Notes |
|---|---|---|---|---|---|---|
| Baseline | TKT-4 | 421 | 3,921 | 58,019 | 1,414 | this file |
| Pagination (page 1) | TKT-5 | 66 | 60 | 61 | 53 | page 1 of each scenario; HTML 12 KB; deep page 183 ms (below) |
| Eager loading | TKT-6 | 49 | 42 | 44 | 4 | page 1 of each scenario; deep page 162 ms (below) |
| Composite index | TKT-7 | | | | | |
| Score reader | TKT-8 | | | | | |

## After pagination (TKT-5, 2026-11-07)

Same machine, same conditions, same method (median of 5 after a warm-up). Pagination shows 50 rows per page; "page 1" is what a user sees first.

| Scenario | Rows | SQL queries run | Query-cache hits | Median ms (min-max) | HTML size |
|---|---|---|---|---|---|
| Company 02, assessment dates in 2024, page 1 | 50 | 53 | 0 | 66 (62-71) | 12 KB |
| Company 02, all rows, page 1 | 50 | 52 | 1 | 60 (58-64) | 12 KB |
| Company 01 (largest), all rows, page 1 | 50 | 53 | 0 | 61 (58-63) | 12 KB |
| Company 01 (largest), page 3,000 (offset 149,950) | 50 | 53 | 0 | 183 (174-192) | 12 KB |

| Scenario | Before | After (page 1) | Change |
|---|---|---|---|
| Normal user (Company 02, 2024): time | 421 ms | 66 ms | 6.4 times faster |
| Normal user: SQL queries | 1,414 | 53 | 27 times fewer |
| Company 02, all rows: time | 3,921 ms | 60 ms | 65 times faster |
| Company 02, all rows: SQL queries | 14,787 | 52 | 284 times fewer |
| Company 01 (largest): time | 58,019 ms | 61 ms | 950 times faster |
| Company 01: SQL queries | 199,064 | 53 | 3,756 times fewer |
| Company 01: page size | 37,287 KB | 12 KB | 3,100 times smaller |

Load test (`ab`, same normal-user page, 20 requests): concurrency 1: 2.44 to 15.40 requests per second (mean 410 ms to 65 ms); concurrency 3: 2.98 to 29.26 requests per second (mean 1,006 ms to 102 ms). A longer run (200 requests at concurrency 3): 28.20 requests per second, mean 106 ms, no failures.

EXPLAIN of the main query: page 1 is now a top-N heapsort (memory 102 kB) over a parallel sequential scan, 39.6 ms. A deep page (page 3,000) needs an external merge sort on disk (about 100 MB of temporary files), 146 ms in the database and 183 ms for the page. So pages deep in the list cost about three times a first page. That is the cost of offset pagination without an index; TKT-7's index is the planned fix and will be measured the same way.

What is left: each page still runs about 50 employee queries (the N+1, TKT-6), and the database still scans and sorts the whole company to find the first 50 rows (TKT-7).

**Page 1 is unchanged (Req 27):** `dashboard:snapshot` for both views (the largest company with no filters, and with the 2024 filter) is byte-for-byte identical to the committed baseline snapshots (sha256 `92cb8fea...` and `acd21db3...`).

## After eager loading (TKT-6, 2026-11-07)

Same machine, conditions and method. The page's employees now arrive in one query that selects only `id` and `email`, instead of one query per row.

| Scenario | Rows | SQL queries run | Median ms (min-max) | HTML size |
|---|---|---|---|---|
| Company 02, assessment dates in 2024, page 1 | 50 | 4 | 49 (46-58) | 12 KB |
| Company 02, all rows, page 1 | 50 | 4 | 42 (41-45) | 12 KB |
| Company 01 (largest), all rows, page 1 | 50 | 4 | 44 (42-46) | 12 KB |
| Company 01 (largest), page 3,000 (offset 149,950) | 50 | 4 | 162 (155-169) | 12 KB |

| Scenario | After pagination (TKT-5) | After eager loading (TKT-6) | Change |
|---|---|---|---|
| Normal user: time | 66 ms | 49 ms | 26% faster |
| Normal user: SQL queries | 53 | 4 | 13 times fewer |
| Company 02, page 1: time | 60 ms | 42 ms | 30% faster |
| Company 01, page 1: time | 61 ms | 44 ms | 28% faster |
| Company 01, page 1: SQL queries | 53 | 4 | 13 times fewer |
| Company 01, deep page 3,000: time | 183 ms | 162 ms | 11% faster |
| `ab`, concurrency 1 | 15.40 requests/s (65 ms) | 19.84 requests/s (50 ms) | 29% more |
| `ab`, concurrency 3 | 29.26 requests/s (102 ms) | 34.10 requests/s (88 ms) | 17% more |
| `ab`, 200 requests, concurrency 3 | 28.20 requests/s (106 ms) | 37.79 requests/s (79 ms) | 34% more |

Against the original baseline (TKT-4) the normal-user page went from 421 ms and 1,414 queries to 49 ms and 4 queries.

- **The query count is constant:** 4 for a page of 3, 20 or 50 rows (a unit test proves it), and 4 on every page measured.
- **The employee query:** `SELECT "employees"."id", "employees"."email" FROM "employees" WHERE "employees"."id" IN (...)`, 0.9 ms for a page; the assessments query still takes about 41 ms.
- **Bullet:** the log stayed empty (0 bytes) across the first, a middle, the last and a past-the-end page, a filtered page and an invalid-filter request: no N+1 and no unused eager loading.
- **Page 1 is unchanged:** both snapshots are identical to the committed baseline (same sha256 values as before).
- **A smaller gain than the query count suggests, as predicted:** the 50 per-row lookups only cost about 15 to 20 ms in total because each is a fast primary-key lookup. What remains is dominated by the main assessments query (about 41 ms), which scans and sorts the whole company without an index; that is TKT-7.
- **A cost noticed on the way:** the status list in the filter form runs `SELECT DISTINCT ... FROM assessments WHERE company_id = ...` (about 59 ms for the largest company) whenever its 10-minute cache is empty. Hot in the benchmark (cached by the warm-up) but a real cost for the first page view after the cache expires. It scans the same rows an index on the company would help; recorded for TKT-7 and the write-up.

## Page-1 snapshots (Req 27)

`dashboard-page1-baseline-default.txt` (the largest company, no filters) and `dashboard-page1-baseline-filtered.txt` (the same company, 2024 only): the first 50 rows as `employee_id | date | status | score | email hash`, with no emails. After each change run `bin/rails dashboard:snapshot` (and `VIEW=filtered`) and diff against these. The only expected difference is the score column after the score reader (TKT-8). If the seed is regenerated, the snapshots must be regenerated and the reason recorded.

## Not measured here

Staging, production and APM (Datadog or similar). In a real environment the same scenarios would be repeated on staging and compared with production APM traces before and after each change; the numbers above are local and relative.
