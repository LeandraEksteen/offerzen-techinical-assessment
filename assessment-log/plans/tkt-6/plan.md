# TKT-6 plan: eager loading on the dashboard

Status: plan, not yet approved. Source ticket: `assessment-log/tickets/TKT-6.md`. Spec: `assessment-log/spec/` (Req 24, 26, 27).

## Why this matters
After pagination, every dashboard page still runs about 53 SQL queries: one per row to look up that row's employee, plus a few fixed ones. The count grows with the page size and Bullet flags it on every request. Fetching all the page's employees in one query makes the count constant (about 5) whatever the page shows, and removes the repeated round trips that the benchmark showed dominate everything except the main query.

## Architecture overview
The controller adds `preload` for the page's employees, through a new association that loads only the employee's id and email (the only things the page shows). Rails then runs one extra query (`SELECT id, email FROM employees WHERE id IN (...)`) for the 50 assessments, instead of 50 separate ones. Nothing else changes: same rows, same order, same filters and paging, same naive score.

## Findings that shape the plan
1. **Preload, not includes or eager_load.** `includes` would choose preload here anyway; `eager_load` joins employees into the main query, which combined with limit, offset and a sort widens every row and complicates the paging. `preload` is two simple queries.
2. **Limiting columns on a preload needs the limit on the association, not on the relation.** `.preload(:employee).select(...)` or a merged `Employee.select` does not apply to the preloaded query. The reliable way is a small association with its own select: `belongs_to :employee_for_listing, -> { select(:id, :email) }, class_name: "Employee", foreign_key: :employee_id`. The existing `belongs_to :employee` stays untouched for everything else.
3. **Loading fewer columns fails loudly if the page later reads another one.** An employee loaded with only id and email raises `ActiveModel::MissingAttributeError` on `name`. That is a useful guard (no silent extra query); a test pins it.
4. **The big assessments column is needed.** The naive score reads `responses_json`, so the assessments query keeps all columns. Narrowing it would change nothing the user sees but would touch the score code TKT-8 replaces, so it is out of scope and noted for TKT-8.
5. **Bullet checks both directions:** it flags a missing eager load (the N+1) and an eager load nobody uses. The view reads the preloaded employee on every row, so it is used; MC-2 confirms the log stays empty.
6. **The PII scrubber is unaffected.** `Employee` declares `name` and `email` as personal data, which only changes `inspect` and log scrubbing; no log or inspect output is added here.
7. **The test environment has no Bullet** (development-only gem), so the "no N+1" requirement is proven in tests by a constant query count and manually with Bullet on.

## Requirements
- Req 24: no N+1 (Bullet silent), constant query count regardless of rows, only needed employee columns loaded, numbers recorded.
- Req 26: one change, measured, revertible alone; a row appended to the benchmarks table.
- Req 27: page 1 unchanged (snapshots), 200 for every filter combination.

## Design

| Piece | What it does |
|---|---|
| `Assessment` | New `belongs_to :employee_for_listing` with `select(:id, :email)`, with a comment saying it exists only for list pages that show the employee's email. `belongs_to :employee` unchanged. |
| `DashboardController#show` | Adds `.preload(:employee_for_listing)` to the paged query. |
| `dashboard/show` view | Reads `assessment.employee_for_listing.email` instead of `assessment.employee.email`. |
| Tests | The TKT-4 characterisation test (query count grows with rows) is replaced by a test that the count is constant; new tests for the selected columns and the loud failure. |
| Benchmarks | A row appended; no benchmark code change. |

## Changes required (single repo)

| File | Change | Complexity |
|---|---|---|
| `app/models/assessment.rb` | One association | Low |
| `app/controllers/dashboard_controller.rb` | One `preload` | Low |
| `app/views/dashboard/show.html.erb` | One word changed | Low |
| `test/` | 7 cases, one flipped | Low |
| `assessment-log/` | Benchmarks row, ticket, decisions, prompts | Low |

No migrations, no gem, no index.

## Contract summary
None. Single-repo change; see `contract.md`.

## PR strategy
One PR, base `main`, branch `feat/TKT-6/dashboard-eager-loading`, title `TKT-6 | Task 2: eager loading on the dashboard`. Yaml in `pr-strategy.yaml`.

## Test matrix

| ID | Req | Case | Type | Bucket | PR |
|---|---|---|---|---|---|
| UT-1 | 24 | The query count is the same for pages of 3, 20 and 50 rows | positive | unit | 1 |
| UT-2 | 24 | Page 1 of 120 rows runs at most 8 SQL queries | positive | unit | 1 |
| UT-3 | 24 | The employee query selects only id and email; loaded employees have no other attribute | positive | unit | 1 |
| UT-4 | 27 | Same emails, rows and order as reading each employee separately | positive | unit | 1 |
| UT-5 | 27 | Several assessments sharing one employee each show that email | edge | unit | 1 |
| UT-6 | 24 | Reading an unloaded employee attribute raises instead of running another query | edge | unit | 1 |
| UT-7 | 27 | Filters, paging, empty and invalid-filter pages behave as before (existing tests unchanged) | positive | unit | 1 |
| MC-1 | 26 | Benchmark after the change; append the row | positive | manual | 1 |
| MC-2 | 24 | Bullet on: log stays empty on first, middle, filtered and last pages | positive | manual | 1 |
| MC-3 | 27 | Snapshots for both views identical to the baseline | positive | manual | 1 |
| MC-4 | 24 | Development log shows one assessments query and one employees query selecting only id and email | positive | manual | 1 |
| MC-5 | 26 | `ab` load test repeated | positive | manual | 1 |

## Risks and mitigations
- **A future change reads another employee column.** It raises in development and test (UT-6) instead of adding a hidden query.
- **Bullet could report "unused eager loading" if a page showed no rows or no emails.** The empty page has no rows to read; Bullet only judges loaded records. MC-2 checks that page too.
- **Page 1 must not change.** UT-4 and the snapshot diff (MC-3).
- **Numbers:** the main query still takes about 40 ms, so expect page 1 to drop by the per-row lookups only (a few milliseconds to ten or so), not to near zero. The honest outcome is recorded either way; the index ticket targets the rest.
- **Invariant writers:** none.

## Open questions (need your decision)
1. **Column-limited association.** Use the new `employee_for_listing` association (loads only id and email) rather than a plain `includes(:employee)`, because Req 24 asks for only the needed columns. The cost is one extra association and the loud failure if another column is read. Accept?
2. **Leave the assessments columns alone.** The naive score needs `responses_json`, so no narrowing of the assessments query here; noted for TKT-8. Accept?

## Out of scope
Pagination changes, indexes (TKT-7), the score reader (TKT-8), narrowing the assessments columns.

## Estimated scope
About 5 files and 150 lines including tests. Single PR.

## Critic pass
Not run as a separate agent: single repo, no contract items.

## Self-check
- Reqs 24, 26 and 27 land in PR 1 with unit cases and manual measurement rows.
- No behaviour decision lives only in this plan: the two open questions are implementation choices and will be recorded in DECISIONS.md; no spec amendment is needed.

## Implementation notes (added after building)
- Built as planned, no scope change. A test helper bug found on the way: clearing a company's rows through the cached `has_many` target did nothing, so the test now deletes through `Assessment.where`.
- The measured gain (about 25 to 30% per page) is smaller than the query count (13 times fewer) suggests, as the plan predicted: the per-row lookups were cheap primary-key reads and the 41 ms main query dominates.
- Results: `assessment-log/benchmarks/task-2-dashboard.md` (section "After eager loading") and the 2026-11-07 comment in `tickets/TKT-6.md`.

