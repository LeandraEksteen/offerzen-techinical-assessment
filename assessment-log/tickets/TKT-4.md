---
key: TKT-4
type: Task
title: Task 2: baseline dashboard and benchmark method
status: In Review
parent: EPIC-1
updated: 2026-11-07T09:52:08Z
---

## Description
**Context:** Task 2 needs a real before. This ticket adds the legacy-style dashboard and fixes how it will be measured before anything is improved.

**Scope:** One company-scoped table (employee email, employee id, assessment date, status, score as currently stored) with date and status filters using the same semantics as the export; unpaginated with an N+1 on employees; Bullet and rack-mini-profiler in development; a documented measurement script or steps (query count, EXPLAIN ANALYZE, a simple load test with hey or k6) and the baseline numbers recorded on the 500k seed; a regression check that captures page 1 of the big company for later comparison.

**Not in scope:** Any improvement (TKT-5 to TKT-8). Staging, production and APM measurement are described in SOLUTION.md only (Req 39).

**Depends on:** TKT-1

**Spec requirements:** Req 21, Req 22, Req 27 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- Record real numbers, not impressions.
- The score shown here is the naive stored read; the contract reader arrives in TKT-8.
- Dashboard log hygiene is verified in TKT-8.

## Acceptance criteria
- Req 21: The page lists only the signed-in admin's company assessments with columns employee email, employee id, assessment date, status, score; its date and status filters use the same semantics as Req 5 and Req 6; it is visible only to signed-in admins.
- Req 22: A first change adds the unpaginated dashboard with an N+1 on employees; measurements on the 500k seed using Bullet, rack-mini-profiler, EXPLAIN ANALYZE and a simple load test (hey or k6) are recorded as numbers before any improvement; staging, production and APM measurement are described in SOLUTION.md only.
- Req 27: Before and after each change, page 1 of the seeded big company shows the same rows in the same order with the same values (apart from scores fixed by the score reader); the page returns 200 for every status and date filter combination in the seed.

## Definition of done
- PR links this ticket (`TKT-4` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
- 2026-11-07 implementation: baseline `DashboardController`, view and helper (company-scoped, five columns, `Assessment.matching` shared with the export so the two filters cannot disagree, unpaginated, employee read through the association, naive stored score); Bullet and rack-mini-profiler (development only, `BULLET=off` / `MINI_PROFILER=off` switches); `DashboardProbe`, `DashboardBenchmark`, and the `benchmark:dashboard`, `benchmark:explain` and `dashboard:snapshot` tasks; 103 tests (stable over 3 runs), rubocop, brakeman, bundler-audit and typecheck clean. Spec wording amended: Req 22 load test is "ab, hey or k6" (`ab` is installed, the others are not). Baseline on the 500k seed (development, profilers off, median of 5, M1 Pro): normal user (Company 02, 2024) 1,516 rows, 1,414 queries, 421 ms; Company 02 all 15,790 rows, 14,787 queries, 3,921 ms; Company 01 all 200,000 rows, 199,064 queries, 58 s, 37 MB page, 2.09 GB peak memory. Load test with `ab` on the normal-user page: 2.44 requests/s at concurrency 1 (410 ms mean), 2.98 requests/s at concurrency 3 (1,006 ms mean). The main query itself takes only 44 to 153 ms (EXPLAIN ANALYZE), so most of the time is Ruby (per-row objects, per-row employee query, rendering): pagination and eager loading matter more than the index. Findings: the first benchmark showed only 43 queries for 15,790 rows because the seed gave each company only 40 employees and Rails' query cache answered the repeats, so the seeder now creates about one employee per ten assessments and the dev database was re-seeded (this changes the Task 1 test-plan counts, noted in the plan); `ab`, not `hey` or `k6`, is on this machine.
