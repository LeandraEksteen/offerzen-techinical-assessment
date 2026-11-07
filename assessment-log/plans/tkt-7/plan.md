# TKT-7 plan: composite index for the dashboard and export date filter

Status: plan, not yet approved. Source ticket: `assessment-log/tickets/TKT-7.md`. Spec: `assessment-log/spec/` (Req 25, 26, 27).

## Why this matters
After pagination and eager loading, a dashboard page still takes about 44 ms for the largest company and 49 ms for a normal user, almost all of it the database scanning and sorting every assessment of the company to find the first 50. An index on the company and the date lets the database read just those rows. The change must be safe on a large live table: it must not block writes while it builds, and it must be easy to check and to undo.

## Experiments run for this plan (throwaway, on the 500k dev data; none committed)
All numbers are PostgreSQL's own `EXPLAIN (ANALYZE, BUFFERS)` execution times, warm cache. The queries are in `state/experiment-queries.sql`. "Spec'd" is the index the spec names, `(company_id, assessment_date)`; "three-column" adds the id as a third key, `(company_id, assessment_date, id)`; a descending variant `(company_id, assessment_date DESC, id DESC)` behaved the same as the three-column one.

| Query | No index | Spec'd two-column | Three-column |
|---|---|---|---|
| Page 1, largest company | 41.3 ms (parallel scan + sort) | **0.20 ms** (index scan + incremental sort) | 0.07 ms (plain index scan) |
| Normal user, 2024 filter, page 1 | 43.0 ms | **0.14 ms** | 0.12 ms |
| Small company (15), page 1 | 39.8 ms | **0.13 ms** | 0.05 ms |
| Status-filtered page 1 (pending) | 57.3 ms | **0.60 ms** | 0.27 ms |
| Deep page 3,000 (offset 149,950) | 190 ms | 201 ms (no change) | 173 ms (no change) |
| Status options (DISTINCT), largest company | 61 ms | 60 ms (no change) | 59 ms (no change) |
| Export batch by id (no date filter) | 4.9 ms | 4.5 ms (no change) | 4.4 ms (no change) |
| Export batch with a one-year date filter | 27.2 ms | 28.3 ms (no change) | **4.3 ms** (index-only scan) |
| Index size | none | **5.7 MB** | 19 MB |
| Concurrent build time (500,000 rows) | n/a | 0.31 s | 0.50 s |

**Write cost** (single-row insert, one client, 6 s, rolled back): 0.096 ms with no extra index, 0.088 ms with the two-column, 0.101 ms with the three-column; a 100,000-row bulk insert took 1.46 s, 1.28 s and 1.35 s. The differences are inside the noise, so at this size the write overhead is not measurable; each extra index still adds one tree insert per row and some disk, which grows with the table.

**Writes while the index builds** (two clients inserting continuously for 6 s, build started after 2 s):

| Build | Statement time | Inserts | Maximum insert latency | Inserts over 50 ms |
|---|---|---|---|---|
| None (idle) | n/a | 115,596 | 4.7 ms | 0 |
| `CREATE INDEX CONCURRENTLY` | 0.41 s | 114,186 | 19.1 ms | 0 |
| Plain `CREATE INDEX` | 0.28 s | 112,430 | **210.3 ms** | 2 |

The plain build froze writers for as long as it ran; the concurrent build did not. On a 500,000-row table that is a fifth of a second; on a table a hundred times larger it would be tens of seconds to minutes, which is why the spec asks for the concurrent form.

## What the spec assumed that the evidence does not support
1. **The index does not help deep pages.** Page 3,000 still sorts about 150,000 rows on disk (190 ms with or without any candidate): the planner correctly prefers a scan and sort over reading 150,000 index entries and then 150,000 heap rows. The index fixes the pages people actually open (the first ones, by a factor of 200), not offsets deep in the list. Keyset pagination would fix deep pages; it is not planned (D-023).
2. **The index does not help the export's date filter** (Req 25 names "the dashboard and export date filter"). The export reads batches in id order, so the planner keeps using the primary key and filters by date as it goes (27 ms per 5,000 rows for a one-year range). Only the three-column index turns that into an index-only scan (4.3 ms), because it carries the date and the id.
3. **The status list in the filter form (59 to 61 ms on a cache miss) is not helped** by any of the candidates; it needs the status in the index, and the spec forbids a status index. The 10-minute cache stays the mitigation.
4. **No candidate needs a separate status index** (agreed): the status-filtered page already drops from 57 ms to 0.6 ms using only the company and date.

## Architecture overview
One migration creates the index with `CREATE INDEX CONCURRENTLY` (Rails: `add_index ... algorithm: :concurrently`) with the DDL transaction disabled, which PostgreSQL requires for the concurrent form. `down` drops it concurrently. Before creating, the migration drops a leftover INVALID index of the same name: a concurrent build that is interrupted or fails leaves one, and Rails' `if_not_exists` would see it and skip rebuilding, leaving a useless index. No application code changes.

## Requirements
- Req 25: one index on `(company_id, assessment_date)`, concurrent, validity checked, EXPLAIN before and after, no status index, rollback by concurrent drop.
- Req 26: one change, measured; a row appended to the benchmarks table.
- Req 27: page 1 unchanged (snapshots); every filter combination still 200.

## Design

| Piece | What it does |
|---|---|
| Migration `AddCompanyDateIndexToAssessments` | `disable_ddl_transaction!`; `up` drops an invalid leftover named `index_assessments_on_company_id_and_assessment_date` if present, then `add_index :assessments, %i[company_id assessment_date], algorithm: :concurrently`; `down` is `remove_index ... algorithm: :concurrently`. |
| `db/schema.rb` | Gains `t.index ["company_id", "assessment_date"], name: "index_assessments_on_company_id_and_assessment_date"`. |
| Validity check | Tests read `pg_index` (`indisvalid` and `indisready` both true) for that index. The same SQL goes into SOLUTION.md for operators: `SELECT c.relname, i.indisvalid, i.indisready FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE i.indrelid = 'assessments'::regclass;` |
| Old test | "has no secondary index on the assessments table" becomes tests that the index exists, is valid and ready, and is the only secondary index (no status index). |
| Heroku-like release phase | Documented in SOLUTION.md: run the migration in the release phase; the code works with or without the index so order does not matter; the build waits for older open transactions and can take minutes on a large table; check validity afterwards; if it fails, the migration clears the invalid leftover on retry; rollback is a concurrent drop. |

## Changes required (single repo)

| File | Change | Complexity |
|---|---|---|
| `db/migrate/<timestamp>_add_company_date_index_to_assessments.rb` | The migration | Low |
| `db/schema.rb` | One index line and the version | Low |
| `test/models/assessment_test.rb` (and one new test file for the migration) | Replace the "no index" test; add 5 cases | Medium |
| `assessment-log/` | Benchmarks, plan state, ticket, decisions, prompts | Low |

No application code, gem or seed change.

## Contract summary
None. Single-repo change; see `contract.md`.

## PR strategy
One PR, base `main`, branch `feat/TKT-7/composite-index`, title `TKT-7 | Task 2: composite index for the dashboard and export date filter`. Yaml in `pr-strategy.yaml`.

## Test matrix

| ID | Req | Case | Type | Bucket | PR |
|---|---|---|---|---|---|
| UT-1 | 25 | The migration disables the DDL transaction | positive | unit | 1 |
| UT-2 | 25 | The index exists on (company_id, assessment_date) and is valid and ready | positive | unit | 1 |
| UT-3 | 25 | The only secondary index on assessments is that one (no status index) | negative | unit | 1 |
| UT-4 | 25 | The migration rolls back and re-applies: the index disappears and returns, valid | positive | unit | 1 |
| UT-5 | 25 | A leftover INVALID index is dropped and rebuilt valid on a retry | edge | unit | 1 |
| UT-6 | 27 | Dashboard and export return the same rows and order (existing tests pass unchanged) | positive | unit | 1 |
| MC-1 | 25 | EXPLAIN before and after for page 1, filtered, deep, status options, status-filtered, export batches | positive | manual | 1 |
| MC-2 | 26 | Benchmark after the change; append the row | positive | manual | 1 |
| MC-3 | 27 | Snapshots identical; Bullet log empty | positive | manual | 1 |
| MC-4 | 25 | Real migration on the dev database with writers running: build time, size, maximum write latency vs a plain build | positive | manual | 1 |
| MC-5 | 25 | Migration down then up on the dev database; index valid each time | positive | manual | 1 |
| MC-6 | 26 | `ab` load test repeated | positive | manual | 1 |

## Risks and mitigations
- **A failed or interrupted concurrent build leaves an INVALID index** that slows writes and is never used. The migration drops such a leftover before building, a test simulates one (UT-5), and operators get the validity SQL.
- **The build waits for open transactions** older than its start; a long-running transaction can stall it for minutes. Run it in a quiet window or watch `pg_stat_activity`; recorded in SOLUTION.md.
- **Concurrent index operations cannot run inside a transaction**, so tests that exercise the migration cannot use transactional tests; they run with transactions off in their own test class and always restore the index.
- **Write overhead grows with the table.** Not measurable at 500,000 rows (above), recorded as a limitation with the 5.7 MB size.
- **The test database** loads `db/schema.rb`, which creates the index the ordinary way on an empty table; fine.
- **Page 1 content must not change:** snapshots (MC-3).
- **Invariant writers:** none.

## Open questions (need your decision)
1. **Two columns as the spec says, or three?** The spec names `(company_id, assessment_date)`. It already makes pages 200 times faster (41 ms to 0.2 ms). Adding the id as a third key would make them about 3 times faster still (0.07 ms) and would also make the export's date-range batches 6 times faster (27 ms to 4 ms), but the index is 3.3 times larger (19 MB against 5.7 MB), takes longer to build and costs more per write, and the absolute gain on the dashboard is 0.1 ms. I recommend the two-column index the spec names. Accept, or amend Req 25 to three columns?
2. **Deep pages stay slow.** Accept this as a documented limit (an index cannot fix an offset; keyset pagination would), measured and recorded?
3. **The status list query is not helped** (59 ms on a cache miss, 10-minute cache). Accept, noting the cache as the mitigation?
4. **The validity check** is a test plus the operator SQL plus the migration clearing an invalid leftover. Accept?

## Out of scope
A status index (agreed); any other index; keyset pagination; changes to the score reader or eager loading.

## Estimated scope
About 4 files and 150 lines including tests. Single PR.

## Critic pass
Not run as a separate agent: single repo, no contract items.

## Self-check
- Reqs 25, 26 and 27 land in PR 1 with unit cases and manual measurement rows.
- If Open question 1 is answered "three columns", Req 25's index definition is amended in the spec before building.

## Implementation notes (added after building)
- Built as planned; the choice on open question 1 was the spec'd two-column index. The real migration confirmed the experiments: page 1's main query went from 43 ms to 0.2 ms and a dashboard page from about 46 ms to 7 ms.
- A locale gotcha while measuring: `psql` here prints times with a decimal comma (`489,857 ms` is 489.857 ms, not 490 seconds). The experiments were re-read with `LC_ALL=C`.
- `pgbench` (shipped with PostgreSQL) was used to run concurrent writers and measure per-insert latency while the index built.
- Results: `assessment-log/benchmarks/task-2-dashboard.md` (section "After the composite index") and the 2026-11-07 comment in `tickets/TKT-7.md`.

