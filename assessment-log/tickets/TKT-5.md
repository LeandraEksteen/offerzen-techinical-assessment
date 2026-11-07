---
key: TKT-5
type: Task
title: Task 2: dashboard pagination
status: To Do
parent: EPIC-1
updated: 2026-11-07T08:28:15Z
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
