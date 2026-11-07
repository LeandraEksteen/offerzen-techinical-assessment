---
key: TKT-6
type: Task
title: Task 2: eager loading on the dashboard
status: To Do
parent: EPIC-1
updated: 2026-11-07T08:28:15Z
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
