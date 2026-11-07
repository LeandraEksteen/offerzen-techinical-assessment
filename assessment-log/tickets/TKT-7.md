---
key: TKT-7
type: Task
title: Task 2: composite index for the dashboard and export date filter
status: To Do
parent: EPIC-1
updated: 2026-11-07T08:28:15Z
---

## Description
**Context:** The date filter on a large company scans too much. One composite index supports it without blocking writes.

**Scope:** One index on `(company_id, assessment_date)` created CONCURRENTLY in a migration with the DDL transaction disabled; a validity check; EXPLAIN ANALYZE before and after; rollback is a concurrent drop.

**Not in scope:** A separate index on status (the status filter is trimmed and case-insensitive, so a plain index would not be used). Any other index.

**Depends on:** TKT-6

**Spec requirements:** Req 25, Req 26, Req 27 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- A failed concurrent build leaves an invalid index; the check catches it.
- Note the write overhead of the index in SOLUTION.md.

## Acceptance criteria
- Req 25: One index on (company_id, assessment_date) is created CONCURRENTLY with the migration transaction disabled; a check confirms the index is valid; EXPLAIN ANALYZE before and after shows the change in plan and time; no separate status index is added; rollback is dropping the index concurrently.
- Req 26: Baseline, pagination, eager loading, index and the score reader are separate changes, each revertible alone; each records before and after numbers (time and query count); SOLUTION.md has the before/after note and why each step was chosen; no claim in the docs lacks a number.
- Req 27: Before and after each change, page 1 of the seeded big company shows the same rows in the same order with the same values (apart from scores fixed by the score reader); the page returns 200 for every status and date filter combination in the seed.

## Definition of done
- PR links this ticket (`TKT-7` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
