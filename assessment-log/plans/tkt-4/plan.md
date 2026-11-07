# TKT-4 plan: baseline dashboard and benchmark method

Status: plan, not yet approved. Source ticket: `assessment-log/tickets/TKT-4.md`. Spec: `assessment-log/spec/` (Req 21, 22, 27).

## Why this matters
Task 2 asks for one measurable performance improvement and a before/after note, but the repo has no dashboard to improve. Without a real "before", any later claim is a feeling. This ticket adds a deliberately legacy-style dashboard, fixes how it will be measured, and records the baseline numbers on the 500,000-row seed. Tickets TKT-5 to TKT-8 (pagination, eager loading, index, score reader) are then each measured against it.

## Architecture overview
A signed-in admin opens the dashboard and sees every assessment of their company in one table, newest first, with optional date range and status filters that behave exactly like the export's. It is slow on purpose: no pagination, and each row reads its employee through the association (one query per row). A repeatable in-process benchmark task and a page-1 snapshot task make the measurements and the "page still shows the same rows" check (Req 27) reproducible. Bullet and rack-mini-profiler are added to development for diagnosis.

## What the repo and machine say about the spec's assumptions
1. **`hey` and `k6` are not installed** (the spec names them). `ab` (ApacheBench) is at `/usr/sbin/ab`. See Open questions.
2. **`bullet` (8.3.1) and `rack-mini-profiler` (5.0.0)** are available and support Rails 8; both go in the `development` group only, so CI's test job never loads them.
3. **A 200,000-row unpaginated page is huge** (tens of MB of HTML and 200,000 employee queries). It may take minutes or exhaust memory. That is the baseline, but it must be measured with a time limit and run outside the browser, not by opening the page.
4. **Dev-mode numbers are not production numbers.** Development reloads code and does not cache views, and the profilers add overhead. The plan measures in development with the profilers switched off by an environment variable and says so in the results.
5. **The N+1 only exists if the page reads the employee record.** `assessments.employee_email` is a denormalised copy that would need no join. See Open questions.

## Requirements
- Req 21: one company-scoped table, five columns, filters like the export, signed-in admins only.
- Req 22: baseline dashboard, benchmark method fixed before any change, numbers recorded; staging, production and APM only described.
- Req 27: the page-1 snapshot, and a test that every seed status and date filter combination returns 200.

## Design

| Piece | What it does |
|---|---|
| `DashboardController#show` | Finds rows only through `current_company`, ordered by `assessment_date` descending then `id` descending (the order Req 23 will keep). Filters come from `ExportFilters` and `StatusOptions.condition`, the same as the export. Invalid filters render 422 with a message and no table. Loads everything, with no limit. |
| `dashboard/show` view | Form (GET) with From, To and Status; table with employee email (read as `assessment.employee.email`, the N+1), employee id, assessment date, status as stored, and score. Score is the naive stored read: the top-level `score` as is when the JSON is an object, blank otherwise, never an error. The deliberately naive code carries a comment that TKT-8 replaces it. |
| Routes, home link | `resource :dashboard, only: :show`; a link on the home page. |
| Development gems | `bullet` and `rack-mini-profiler` in the development group. Bullet logs to its own log and the Rails log (class and association names only). Both can be switched off with `BULLET=off` and `MINI_PROFILER=off` for timing. |
| `benchmark:dashboard` task | In-process (a Rails integration session, so the full stack runs) as seeded admins. Refuses to run outside development. For each scenario: one warm-up, then the median of 5 runs of rows, SQL query count (from `sql.active_record`), milliseconds and HTML bytes, with a per-scenario time limit. Prints a markdown table. Never prints emails or the password. |
| `benchmark:explain` task | Runs `EXPLAIN (ANALYZE, BUFFERS)` for the dashboard's main query for a scenario and prints the plan (no personal data in it). |
| `dashboard:snapshot` task | Requests the dashboard as the big company's admin, parses the first 50 table rows, and prints `employee_id | date | status | score | short hash of the email`. Later tickets re-run it against their page 1 and diff (Req 27). |
| `assessment-log/benchmarks/task-2-dashboard.md` | The recorded baseline: method, machine, scenarios, numbers, EXPLAIN plan, load-test output, tool versions. TKT-5 to TKT-8 append a row each. |

**Scenarios (proposed):** (a) normal user: Company 02 with a one-year date filter (about 1,500 rows); (b) Company 02, all rows (15,790); (c) the big company, all rows (200,000), with a 10-minute limit. Whatever happens in (c), including "did not finish", is the baseline.

## Changes required (single repo)

| File | Change | Complexity |
|---|---|---|
| `Gemfile`, `Gemfile.lock` | `bullet`, `rack-mini-profiler` (development) | Low |
| `config/environments/development.rb`, `config/initializers/` | Bullet and profiler settings with off switches | Low |
| `config/routes.rb`, home view | Dashboard route and link | Low |
| `app/controllers/dashboard_controller.rb`, `app/views/dashboard/show.html.erb` | The baseline dashboard | Medium |
| `lib/tasks/benchmark.rake`, `lib/tasks/dashboard.rake` | Benchmark, explain and snapshot tasks | Medium |
| `test/` | 11 unit and integration cases | Medium |
| `assessment-log/` | Benchmarks file, snapshot, ticket, decisions, prompts | Low |

No migrations (the index is TKT-7's).

## Contract summary
None. Single-repo change; boundaries checked are in `contract.md`.

## PR strategy
One PR, base `main`, branch `feat/TKT-4/baseline-dashboard-benchmark`, title `TKT-4 | Task 2: baseline dashboard and benchmark method`. Yaml in `pr-strategy.yaml`.

## Test matrix

| ID | Req | Case | Type | Bucket | PR |
|---|---|---|---|---|---|
| UT-1 | 21 | Only the signed-in admin's company, with the five columns | positive | unit | 1 |
| UT-2 | 21 | Signed-out visitors are redirected to sign-in | negative | unit | 1 |
| UT-3 | 21 | Filters select exactly the rows the export selects for the same filters | positive | unit | 1 |
| UT-4 | 21 | Status select offers the company's own grouped statuses | positive | unit | 1 |
| UT-5 | 21 | Start date after end date gives 422, a message and no table | negative | unit | 1 |
| UT-6 | 27 | Ordered by assessment date descending, then id descending | edge | unit | 1 |
| UT-7 | 27 | Every score shape renders without error; stored value shown as is, blank when absent | edge | unit | 1 |
| UT-8 | 22 | The baseline reads each employee separately; query count grows with rows | positive | unit | 1 |
| UT-9 | 21 | The dashboard leaves no emails, response content or raw scores in the captured log | positive | unit | 1 |
| UT-10 | 27 | The snapshot task prints the first 50 rows with a stable digest and no emails | positive | unit | 1 |
| UT-11 | 22 | The benchmark task prints rows, queries, ms and bytes per scenario and refuses outside development | positive | unit | 1 |
| MC-1 | 22 | Run the three scenarios on the 500k seed and record the numbers | positive | manual | 1 |
| MC-2 | 22 | Bullet reports the N+1 in the development log | positive | manual | 1 |
| MC-3 | 22 | The rack-mini-profiler badge appears and lists the repeated query | positive | manual | 1 |
| MC-4 | 22 | EXPLAIN ANALYZE of the main query recorded | positive | manual | 1 |
| MC-5 | 22 | Load test with `ab` on the normal-user page recorded | positive | manual | 1 |

## Risks and mitigations
- **The big scenario may not finish.** Per-scenario time limit; "did not finish within 10 minutes" is a valid recorded baseline. Never opened in the browser.
- **Profilers distort timings.** Off during timing, on only for MC-2 and MC-3.
- **Numbers vary between machines and runs.** Median of 5 after a warm-up; machine, Ruby and Postgres versions recorded; the claim is relative (before versus after on the same machine).
- **The characterisation test (UT-8) asserts bad behaviour.** Deliberate; TKT-6 flips it to "constant query count".
- **Snapshot drift.** It depends on the deterministic seed; if the seed is regenerated, the snapshot is regenerated and the reason recorded.
- **Personal data:** emails are shown to the signed-in admin only, never logged (UT-9), and the committed snapshot holds only a short hash of each email.
- **Benchmark task signs in with the seeded password.** Development only, refuses elsewhere, never prints it.
- **Invariant writers:** none.

## Open questions (need your decision)
1. **Load-test tool.** `hey` and `k6` are not installed; `ab` is. Use `ab` and amend Req 22's wording to "ab, hey or k6", or do you want `brew install hey` (installs software on your machine)? I recommend `ab`.
2. **Where the email comes from.** The page reads the employee record (`assessment.employee.email`), which creates the N+1 and is how a legacy page would plausibly show a person; the denormalised `assessments.employee_email` stays unused here. Confirm?
3. **Naive score.** Show the top-level `score` exactly as stored when the JSON is an object, blank otherwise (so "85%", `0.85`, `150` and `"N/A"` show as they are). Confirm as the baseline?
4. **Scenarios and conditions.** The three scenarios above, in development with profilers off, median of 5 after a warm-up, 10-minute limit for the big one. Confirm? (A production-mode run would need precompiled assets; not planned.)
5. **Snapshot content.** Employee id, date, status, score and a short hash of the email (no emails in committed files). Confirm?

## Out of scope
Any improvement (TKT-5 to TKT-8); the dashboard's log hygiene (Req 14, TKT-8, though this ticket must not log data); staging, production and APM (SOLUTION.md only, Req 39).

## Estimated scope
About 14 files and 600 lines including tests. Single PR.

## Critic pass
Not run as a separate agent: single repo, no contract items.

## Self-check
- Reqs 21, 22 and 27 all land in PR 1 with unit cases; Req 22's measurements are manual rows MC-1 to MC-5.
- One wording change to the spec is proposed (the load-test tool in Req 22) and will be written back with an amendment after approval.

## Implementation notes (added after building)
- Scope grew: `Assessment.matching` (app/models) is now the single owner of the two filters and the export uses it (small change in `app/services/assessment_csv_export.rb`); the probe and benchmark classes live in `lib/`; the seeder (`lib/assessment_seeder.rb`) was changed (see below).
- **Seed change (finding):** the first run showed 43 SQL queries for 15,790 rows. With only 40 employees per company, Rails' per-request query cache answered the repeated employee lookups, hiding the N+1. The seeder now creates about one employee per ten assessments (a yearly assessment over ten years) and the dev database was re-seeded; the real N+1 then showed (14,787 queries for 15,790 rows). The benchmark now reports query-cache hits separately.
- **Benchmark tool:** `ab` was used for the load test (the spec was amended).
- **Stale server:** an old server on port 3055 once hid the new gems; killed and restarted before the Bullet and profiler checks.
- Results and findings: `assessment-log/benchmarks/task-2-dashboard.md` and the 2026-11-07 comment in `tickets/TKT-4.md`.

