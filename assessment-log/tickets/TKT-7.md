---
key: TKT-7
type: Task
title: Task 2: composite index for the dashboard and export date filter
status: In Review
parent: EPIC-1
updated: 2026-11-07T10:23:37Z
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
- 2026-11-07 implementation: migration `AddCompanyDateIndexToAssessments` adds one index on `(company_id, assessment_date)` with `algorithm: :concurrently` and `disable_ddl_transaction!`, clears an INVALID leftover of the same name before building, and `down` drops it concurrently; `db/schema.rb` gains the index. The old "no secondary index" test is replaced by `test/db/composite_index_test.rb` (migration disables the DDL transaction; index exists on company and date and is valid and ready via `pg_index`; the only secondary index, no status index; down and up round trip; a simulated invalid leftover is dropped and rebuilt valid). Checks: 124 tests (stable over 3 runs), rubocop, brakeman, bundler-audit clean. Evidence from throwaway experiments first (three candidate indexes, plans, size, write overhead, writes during a build) is in the plan. Results on the 500k seed (median of 5, profilers off): page 1 normal user 51 ms to 8 ms, Company 02 47 to 7 ms, Company 01 46 to 7 ms (main query 43 ms to 0.2 ms); deep page 164 vs 176 ms (no change); `ab` concurrency 1: 18.80 to 123.69 requests/s, concurrency 3: 37.20 to 128.50. From the original baseline the largest company's first view went from 58,019 ms to 7 ms. Real migration on the dev database with two writers: built in 0.34 s, maximum insert latency 10.0 ms, none over 50 ms (plain build in the comparison: 210 ms maximum, two over 50 ms). Bullet log empty; both page-1 snapshots identical; migration down and up verified. Findings: the index does not help deep pages, the export's date-range batches (they use the primary key) or the status list query (about 58 ms on a cache miss); a three-column index would help the export range 6 times but is 3.3 times larger (not chosen).
