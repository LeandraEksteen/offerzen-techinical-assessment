---
key: TKT-5
type: Task
title: Task 2: dashboard pagination
status: In Review
parent: EPIC-1
updated: 2026-11-07T10:02:22Z
---

## Description
**Context:** Pagination is the first and probably biggest win for large companies.

**Scope:** 50 rows per page with Previous and Next only (fetch one extra row to detect a next page); bad page values handled; stable order (assessment date descending, then id descending); filters kept in page links; before and after numbers recorded.

**Not in scope:** Total counts, page-size selector, eager loading, indexing.

**Depends on:** TKT-4

**Spec requirements:** Req 23, Req 26, Req 27 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- A total count would itself be slow on a large company, which is why there is none.
- Verify page 1 content is unchanged apart from ordering guarantees.

## Acceptance criteria
- Req 23: The dashboard shows 50 rows per page with Previous and Next only (next detected by fetching one extra row); page values like abc, -1 or past the last page show page 1 or an empty last page with status 200; order is assessment_date descending then id descending; filters survive in page links; measured time and query count before and after are recorded.
- Req 26: Baseline, pagination, eager loading, index and the score reader are separate changes, each revertible alone; each records before and after numbers (time and query count); SOLUTION.md has the before/after note and why each step was chosen; no claim in the docs lacks a number.
- Req 27: Before and after each change, page 1 of the seeded big company shows the same rows in the same order with the same values (apart from scores fixed by the score reader); the page returns 200 for every status and date filter combination in the seed.

## Definition of done
- PR links this ticket (`TKT-5` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
- 2026-11-07 implementation: `DashboardController` fetches 51 rows at the page offset and shows 50 (the extra row only signals a next page, so there is no total count); a page value that is not a whole number from 1 to 1,000,000 shows page 1; a page past the last shows an empty page with a message, Previous and a First page link (status 200); Previous and Next carry only the date and status filters; order unchanged. No gem. The benchmark gained a deep-page scenario and page-1 labels. Spec wording amended (Req 23: page-value limits and past-the-end behaviour). Checks: 115 tests (stable over 3 runs), rubocop, brakeman, bundler-audit clean. Results on the 500k seed (median of 5, profilers off): normal user 421 ms to 66 ms and 1,414 to 53 queries; Company 02 all rows 3,921 ms to 60 ms and 14,787 to 52 queries; Company 01 58,019 ms to 61 ms, 199,064 to 53 queries, 37,287 KB to 12 KB; deep page (3,000) 183 ms. `ab`, concurrency 1: 2.44 to 15.40 requests/s; concurrency 3: 2.98 to 29.26 requests/s. Page-1 snapshots (both views) are identical to the baseline. Browser check on the largest company: page 4000 is the last (200,000 rows), 4001 and 999999 are empty pages, abc, -1, 0, 1.5 and a 21-digit number show page 1, status filters and invalid filters behave.
