---
key: TKT-6
type: Task
title: Task 2: eager loading on the dashboard
status: In Review
parent: EPIC-1
updated: 2026-11-07T10:11:18Z
---

## Description
**Context:** Remove the N+1 on employees.

**Scope:** Eager load only the employee columns the page needs; Bullet clean; constant query count regardless of row count; before and after numbers recorded.

**Not in scope:** Pagination, indexing, score reader.

**Depends on:** TKT-5

**Spec requirements:** Req 24, Req 26, Req 27 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- One query count that does not grow with rows is the acceptance, not a feeling.

## Acceptance criteria
- Req 24: Bullet reports no N+1 on the dashboard; the query count for a page is constant regardless of rows; only the employee columns the page needs are loaded; before and after numbers are recorded.
- Req 26: Baseline, pagination, eager loading, index and the score reader are separate changes, each revertible alone; each records before and after numbers (time and query count); SOLUTION.md has the before/after note and why each step was chosen; no claim in the docs lacks a number.
- Req 27: Before and after each change, page 1 of the seeded big company shows the same rows in the same order with the same values (apart from scores fixed by the score reader); the page returns 200 for every status and date filter combination in the seed.

## Definition of done
- PR links this ticket (`TKT-6` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
- 2026-11-07 implementation: new column-limited association `Assessment#employee_for_listing` (`select(:id, :email)`), `preload` in `DashboardController`, and the view reads it; `belongs_to :employee` untouched. The TKT-4 characterisation test (query count grows with rows) is replaced by one proving the count is constant, plus tests for the 8-query ceiling, the employee query selecting only id and email, loaded employees having no other attribute, a loud `MissingAttributeError` on an unloaded one, same emails/rows/order, and shared employees. Checks: 120 tests (stable over 3 runs), rubocop, brakeman, bundler-audit clean. Results on the 500k seed (median of 5, profilers off): normal user 66 ms to 49 ms and 53 to 4 queries; Company 02 page 1 60 to 42 ms; Company 01 page 1 61 to 44 ms; deep page 183 to 162 ms; `ab` concurrency 1: 15.40 to 19.84 requests/s, concurrency 3: 29.26 to 34.10. From the original baseline the normal-user page is 421 ms/1,414 queries to 49 ms/4 queries. Bullet log empty across first, middle, last, past-the-end, filtered and invalid-filter requests (no N+1, no unused eager loading). Page-1 snapshots identical to the baseline. Development log shows one assessments query and one `SELECT "employees"."id", "employees"."email"` query per page. Finding: the filter form's status list query (`SELECT DISTINCT ... FROM assessments WHERE company_id`) takes about 59 ms for the largest company whenever its 10-minute cache is empty; recorded for TKT-7.
