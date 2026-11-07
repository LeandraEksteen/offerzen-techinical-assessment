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
| Composite index | TKT-7 | 8 | 7 | 7 | 4 | page 1 of each scenario; main query 43 ms to 0.2 ms; deep page unchanged (176 ms) |
| Score reader | TKT-8 | 7 | 6 | 6 | 4 | page 1 of each scenario; deep page 95 ms (run to run noise, no change intended); 200,000-row export median 2,552 ms (was 3,767) |

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

## After the composite index (TKT-7, 2026-11-07)

One index on `assessments (company_id, assessment_date)`, built `CONCURRENTLY`. Same machine, conditions and method (median of 5 after a warm-up). The "before" runs below were repeated immediately before the migration.

| Scenario | Before the index | After the index | Change |
|---|---|---|---|
| Normal user (Company 02, 2024), page 1 | 51 ms | 8 ms | 6.4 times faster |
| Company 02, all rows, page 1 | 47 ms | 7 ms | 6.7 times faster |
| Company 01 (largest), page 1 | 46 ms | 7 ms | 6.6 times faster |
| Company 01, deep page 3,000 | 164 ms | 176 ms | no change (noise) |
| SQL queries per page | 4 | 4 | none |
| `ab`, concurrency 1 | 18.80 requests/s (53 ms) | 123.69 requests/s (8 ms) | 6.6 times more |
| `ab`, concurrency 3 | 37.20 requests/s (81 ms) | 128.50 requests/s (23 ms) | 3.5 times more |
| `ab`, 200 requests, concurrency 3 | 36.82 requests/s (81 ms) | 145.56 requests/s (21 ms) | 4.0 times more |

EXPLAIN (ANALYZE, BUFFERS), the dashboard's main query (`dashboard-explain-before-index.txt`, `dashboard-explain-after-index.txt`):

| Scenario | Plan before | Time before | Plan after | Time after |
|---|---|---|---|---|
| Normal user, page 1 | parallel sequential scan, top-N sort | 46.4 ms | index scan backward, incremental sort | 0.15 ms |
| Largest company, page 1 | parallel sequential scan, top-N sort | 43.0 ms | index scan backward, incremental sort | 0.21 ms |
| Largest company, page 3,000 | parallel sequential scan, external disk sort | 139.7 ms | parallel sequential scan, external disk sort (unchanged) | 165.7 ms |

The planner uses the index for the first pages but, for an offset of 149,950, still prefers scanning and sorting the company: reading 150,000 index entries and then 150,000 table rows is dearer. **The index fixes the pages people open, not deep offsets.** Keyset pagination would fix those; it is not planned (D-023).

Other queries (PostgreSQL execution time, warm; the eight queries are in `index-experiments-queries.sql`):

| Query | No index | With the index |
|---|---|---|
| Page 1, largest company | 41.3 ms | 0.06 ms |
| Normal user, 2024 filter, page 1 | 43.0 ms | 0.06 ms |
| Small company (15), page 1 | 39.8 ms | 0.06 ms |
| Status-filtered page 1 (pending) | 57.3 ms | 0.30 ms |
| Deep page 3,000 | 190 ms | 193 ms |
| Status list (`SELECT DISTINCT`), largest company | 61.3 ms | 57.5 ms (not helped) |
| Export batch by id, no date filter | 4.9 ms | 4.1 ms (unchanged: uses the primary key) |
| Export batch with a one-year date filter | 27.2 ms | 27.0 ms (unchanged: uses the primary key) |

### Build, size and writes

- **Build:** 0.34 s concurrently on 500,000 rows (0.30 s on a second run; a plain, blocking build took 0.19 to 0.28 s). Index size 5.7 MB on a clean table (7.6 MB after the experiments added dead rows).
- **Write overhead (throwaway experiments):** a single-row insert took 0.096 ms with no extra index and 0.088 ms with this index; a 100,000-row bulk insert took 1.46 s and 1.28 s. The differences are inside the noise, so the cost is not measurable at this size; each index still adds one tree insert per row and disk that grows with the table.
- **Writes while it builds** (two clients inserting continuously; 265,328 inserts in 14 s while the real migration ran): maximum insert latency 10.0 ms, none over 50 ms. In the throwaway comparison (6 s, two clients): idle 4.7 ms maximum; concurrent build 19.1 ms maximum and no insert over 50 ms; a plain `CREATE INDEX` froze writers, maximum 210.3 ms with two inserts over 50 ms. On a table a hundred times larger a plain build would block writes for tens of seconds to minutes.
- **Bullet:** the log stayed empty (0 bytes) across first, middle, last, past-the-end, filtered, status-filtered and invalid-filter requests.
- **Page 1 unchanged:** both snapshots are identical to the committed baseline.
- **Migration down and up on the dev database:** the index is dropped (0.005 s) and rebuilt (0.30 s), valid and ready each time.

### Three-column alternative (evaluated, not chosen)

`(company_id, assessment_date, id)` made the dashboard's first pages about three times faster again (page 1: 0.07 ms against 0.20 ms in the same experiment) and turned the export's one-year date batches into an index-only scan (27 ms to 4.3 ms), but the index is 19 MB against 5.7 MB, takes longer to build (0.50 s against 0.31 s) and costs more per write. The absolute gain on a dashboard page is about 0.1 ms. The spec's two-column index was kept; the three-column one is the documented option if the export's date filter becomes a hot path.

### What is still slow

- Deep pages (the cost of offset pagination).
- The status list in the filter form: `SELECT DISTINCT` over the company's rows, about 58 ms on a cache miss (10-minute cache); no index allowed by the spec helps it.
- Nothing else in Task 2 is open; the score reader (TKT-8) changes what the Score column shows and did not slow the page or the export.

## After the score reader (TKT-8, 2026-11-07)

The reader reads the four candidate keys in SQL (`responses_json->'score'` and the three aliases) instead of loading the whole JSON or evaluating the old SQL score, then interprets them in Ruby (`ScoreReader`).

| Scenario | Before (TKT-7) | After |
|---|---|---|
| Normal user, 2024, page 1 | 7 ms | 7 ms (6-15) |
| Company 02, all rows, page 1 | 7 ms | 6 ms (6-13) |
| Company 01 (largest), page 1 | 6 ms | 6 ms (6-11) |
| Company 01, page 3,000 | 164 ms | 95 ms (93-99); not a goal, same query shape, so treat as noise |
| SQL queries per page | 4 | 4 |
| 200,000-row CSV export (median of 3, to a null IO) | 3,767 ms (3,496 / 3,767 / 4,002) | 2,552 ms (3,971 / 2,552 / 2,452; first run cold) |
| `ab`, filtered page, c=1, 40 requests, warm server | 123.69 req/s (20 requests) | 157.13 req/s, 99th percentile 9 ms |
| `ab`, c=3 | 128.50 req/s | 172.57 req/s, 99th percentile 19 ms |

The two `ab` runs are not strictly comparable (20 against 40 requests, warm against first run) but show no regression. A first run on a cold server measured 76 and 170 req/s because the first request pays for code loading.

- **Page 1 content:** `dashboard:snapshot` (default and `VIEW=filtered`) diffed against the baseline files: 0 differences in the date, status, employee id and email-hash columns on all 50 rows of each view; the score column changed on 19 (default) and 16 (filtered) rows, all of them the expected cases (a blank, `N/A` or out-of-range value now reads "Score not available"; `43%` reads 43; `49.99999` reads 50; `60.5` reads 61; `150` is rejected). The new snapshots are `dashboard-page1-after-score-default.txt` and `-filtered.txt`.
- **Bullet:** with Bullet on and 40 + 40 dashboard requests, the log stayed empty (0 bytes).
- **Report on the 500k seed:** `score-report-500k-seed.txt`, 2.8 seconds, no email or free text in the output.

## Page-1 snapshots (Req 27)

`dashboard-page1-baseline-default.txt` (the largest company, no filters) and `dashboard-page1-baseline-filtered.txt` (the same company, 2024 only): the first 50 rows as `employee_id | date | status | score | email hash`, with no emails. After each change run `bin/rails dashboard:snapshot` (and `VIEW=filtered`) and diff against these. The only expected difference is the score column after the score reader (TKT-8). If the seed is regenerated, the snapshots must be regenerated and the reason recorded.

## Not measured here

Staging, production and APM (Datadog or similar). In a real environment the same scenarios would be repeated on staging and compared with production APM traces before and after each change; the numbers above are local and relative.
