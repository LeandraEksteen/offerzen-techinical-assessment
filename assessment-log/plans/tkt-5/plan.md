# TKT-5 plan: dashboard pagination

Status: plan, not yet approved. Source ticket: `assessment-log/tickets/TKT-5.md`. Spec: `assessment-log/spec/` (Req 23, 26, 27).

## Why this matters
The baseline measured in TKT-4 shows the dashboard is unusable for the largest company: one request builds 200,000 rows, runs 199,064 queries, returns a 37 MB page and uses about 2 GB of memory, taking 58 seconds. Even a normal user waits 421 ms for 1,516 rows. Showing 50 rows at a time is the biggest and lowest-risk change available, and it is measured against that baseline with the same method.

## Architecture overview
The dashboard asks the database for 51 rows starting at the requested page's offset, shows the first 50, and uses the 51st only to know that a Next page exists. There is no total count (a count over a large company would cost a full scan). Previous and Next links carry the date and status filters. Everything else (the filters, the order, the naive score, the employee N+1) is deliberately unchanged, so this change is measured on its own.

## Findings that shape the plan
1. **No pagination gem is in the Gemfile** (no pagy, kaminari or will_paginate). The change is about 15 lines of controller code, so none is added.
2. **Offset pagination keeps the spec's wording** ("page values like abc, -1 or past the last page"). The alternative, keyset pagination (a cursor of date and id), would avoid the cost of deep pages but cannot express "page 3", so it is not used here. Offset has a known weakness: the database must still walk and sort the rows it skips, and without an index (TKT-7) that is the whole company. The plan measures a deep page to show this cost instead of hiding it.
3. **The main query is only 44 to 153 ms** (TKT-4's EXPLAIN), so page 1 will still take roughly that long plus a little Ruby; the index ticket is what removes most of it.
4. **The N+1 remains for now:** Bullet will still report it (50 employee queries per page instead of one per row) until TKT-6. The characterisation test from TKT-4 (query count grows with rows) still holds for fewer than 50 rows and stays, with a note.
5. **A huge page number can crash the query.** `page=100000000000000000000` produces an offset larger than PostgreSQL's bigint. It must be treated as invalid, not passed to the database.

## Requirements
- Req 23: 50 rows per page, Previous and Next only, fetch-one-extra, safe page values, stable order, filters kept in the links, before and after numbers.
- Req 26: one change per ticket with measured results appended to the benchmarks table.
- Req 27: page 1 shows the same rows in the same order with the same values; every status and date filter combination returns 200.

## Design

| Piece | What it does |
|---|---|
| `DashboardController#show` | Reads `page`: a whole number from 1 to 1,000,000, otherwise page 1 (this covers `abc`, `-1`, `0`, empty, `1.5` and huge values). Loads `limit 51 offset (page-1)*50` of the existing ordered relation; shows the first 50; sets `has_next` from the 51st. Invalid filters still return 422 with no table and no paging links. |
| `dashboard/show` view | Below the table: "Previous" (only from page 2) and "Next" (only when `has_next`), plus "Page N" and the row range. A page past the end shows "No assessments on this page" with Previous and a link to the first page. The existing table and columns are unchanged. |
| Link helper | Builds a link from only `from`, `to` and `status` plus `page`; no other request parameter is copied. |
| `DashboardBenchmark` | Existing scenarios now measure page 1 (labels updated to say so) and a new deep-page scenario measures Company 01 page 3,000 (offset 149,950). |
| Benchmarks file | A new row in the results table; the narrative gains the deep-page figure and EXPLAIN for it. |

**Why page 1 of the big company is the comparison:** before, "the page" for that company was the whole 200,000 rows (58 s); after, a user's first view is page 1. The deep page shows the cost of offset, which TKT-7's index addresses.

## Changes required (single repo)

| File | Change | Complexity |
|---|---|---|
| `app/controllers/dashboard_controller.rb` | Page parsing, limit and offset, fetch-one-extra | Low |
| `app/views/dashboard/show.html.erb`, `app/helpers/` | Paging links, past-the-end message | Low |
| `lib/dashboard_benchmark.rb` | Page-1 labels and the deep-page scenario | Low |
| `test/` | 11 cases | Medium |
| `assessment-log/` | Benchmarks table, ticket, decisions, prompts | Low |

No migrations, no new gem.

## Contract summary
None. Single-repo change; see `contract.md`.

## PR strategy
One PR, base `main`, branch `feat/TKT-5/dashboard-pagination`, title `TKT-5 | Task 2: dashboard pagination`. Yaml in `pr-strategy.yaml`.

## Test matrix

| ID | Req | Case | Type | Bucket | PR |
|---|---|---|---|---|---|
| UT-1 | 23 | 120 rows give pages of 50, 50 and 20 | positive | unit | 1 |
| UT-2 | 23 | Exactly 50 rows has no Next link; 51 rows has one and shows 50 | edge | unit | 1 |
| UT-3 | 23 | Previous only from page 2, Next only when more rows exist, no total count shown | positive | unit | 1 |
| UT-4 | 23 | Page values abc, -1, 0, empty, 1.5 and a huge number show page 1 with 200 | negative | unit | 1 |
| UT-5 | 23 | A page past the last returns 200 with an empty message and a way back | edge | unit | 1 |
| UT-6 | 23 | Same-date rows: the pages together hold every row once, in id-descending order | edge | unit | 1 |
| UT-7 | 23 | Links keep the date and status filters and copy no other parameter | positive | unit | 1 |
| UT-8 | 27 | Page 1 shows exactly the first 50 rows of the full ordered list | positive | unit | 1 |
| UT-9 | 23 | A page's SQL query count is bounded by the page size, not the row count | positive | unit | 1 |
| UT-10 | 27 | Invalid filters still return 422 with no table and no paging links | negative | unit | 1 |
| UT-11 | 26 | The benchmark has page-1 scenarios and a deep page and reports 50 rows each | positive | unit | 1 |
| MC-1 | 26 | Benchmark after the change; append the row to the table | positive | manual | 1 |
| MC-2 | 27 | Snapshot task output equals the committed baseline snapshots | positive | manual | 1 |
| MC-3 | 26 | Deep-page timing and EXPLAIN recorded | positive | manual | 1 |
| MC-4 | 23 | Browser walk-through on the largest company | positive | manual | 1 |
| MC-5 | 26 | `ab` load test on the normal-user page repeated | positive | manual | 1 |

## Risks and mitigations
- **Deep pages are slow without an index.** Measured and recorded rather than hidden; TKT-7 is the fix. A hard cap of 1,000,000 on the page number keeps offsets valid.
- **Rows can shift between pages if data changes while someone pages** (offset pagination's usual weakness). Accepted for a dashboard; the stable order (date, then id) prevents duplicates and gaps in unchanged data (UT-6).
- **Page 1 content must not change.** Proven by UT-8 and by diffing the committed snapshots (MC-2).
- **Links must not leak other parameters.** Only `from`, `to`, `status` and `page` are built into links (UT-7).
- **Bullet still reports the N+1.** Expected until TKT-6; noted so nobody mistakes it for a regression.
- **Invariant writers:** none.

## Open questions (need your decision)
1. **Offset or keyset?** Offset with page numbers keeps Req 23's wording and is simplest; keyset is better for deep pages but cannot express page numbers. Use offset?
2. **Page value limits.** Anything that is not a whole number from 1 to 1,000,000 shows page 1. Accept?
3. **Past the last page.** An empty table with a message, Previous, and a link to the first page (status 200). Accept?
4. **Benchmark scenarios.** Existing scenarios now measure page 1 (the baseline for them was the full page), plus a deep page (Company 01, page 3,000). The deep page has no "before" because pages did not exist. Accept?

## Out of scope
Total counts, a page-size selector, eager loading (TKT-6), indexes (TKT-7), the score reader (TKT-8).

## Estimated scope
About 8 files and 300 lines including tests. Single PR.

## Critic pass
Not run as a separate agent: single repo, no contract items.

## Self-check
- Reqs 23, 26 and 27 land in PR 1 with unit cases; the measurements are manual rows MC-1 to MC-5.
- No behaviour decision lives only in this plan: the page-value limit and past-the-end behaviour are open questions and will be written back to the spec (Req 23) after approval.


## Implementation notes (added after building)
- Built as planned, no scope change beyond a small `lib/tasks/dashboard.rake` edit (EXPLAIN now explains the paginated query and supports the deep page), which is inside the existing `lib/` scope of TKT-4's task files.
- The pager is a `nav` element so tests (and screen readers) can tell it from other links.
- Results: `assessment-log/benchmarks/task-2-dashboard.md` (section "After pagination") and the 2026-11-07 comment in `tickets/TKT-5.md`.
