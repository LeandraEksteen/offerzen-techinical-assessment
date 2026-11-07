---
key: TKT-11
type: Task
title: Task 3: status report and the backfill, release and rollback plan
status: In Review
parent: EPIC-1
updated: 2026-11-07T08:28:15Z
---

## Description
**Context:** Historical statuses must reach the canonical set safely. This is a plan only: nothing in the repo updates historical rows.

**Scope:** A read-only rake task printing distinct statuses as stored with row count and latest `updated_at`, plus mapped-result counts and unmapped count when a mapping file exists; the SOLUTION.md sections for the mapping sheet and the versioned mapping file, the change request outline, the new-column plan with dual-write and a single owner of the column name, the step-by-step Heroku-style release and rollback plan (live-safe steps versus the low-traffic window), lock and responsiveness safeguards with pause thresholds, backup right before the rename.

**Not in scope:** Executing any migration or backfill; a database constraint; the assessor-side front end and API changes outside this repo (described only).

**Depends on:** TKT-10

**Spec requirements:** Req 31, Req 32, Req 33, Req 34, Req 42, Req 43 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- Pause thresholds agreed: replication lag over 5 seconds, any lock wait over 2 seconds, request latency over 1.5 times baseline.
- Share only distinct values with counts and latest updated_at, never rows or ids; scan for free text first.

## Acceptance criteria
- Req 31: SOLUTION.md describes the sheet (only distinct status values with a row count and latest updated_at, never rows or ids, scanned for free text before sharing), assessor confirmation for doubtful values, and a versioned mapping file in the repo used by the backfill; the author's draft aliases are only a starting guess; a value without an approved mapping stays NULL in the new column and blocks the switch.
- Req 32: SOLUTION.md states the legacy column keeps receiving the canonical value after the alias switch until it is dropped; rollback is a code deploy before the rename and the reverse rename after it; a pg:backups:capture is taken immediately before the rename; restoring a backup is described as the last resort because it loses later writes.
- Req 33: A rake task reads in batches without writing and prints one row per distinct status value (as stored) with a count and the latest updated_at; once a mapping file exists it also prints counts per mapped result and the number of unmapped values; the code contains no path that updates historical statuses.
- Req 34: The plan lists in order: (1) add a nullable column (instant) and deploy code writing both columns; (2) backfill in batches of about 5,000 ids from a one-off dyno, throttled, resumable, idempotent; (3) verify 100% filled and no unmapped; (4) switch the app to the new column with an alias; (5) keep writing the legacy column; (6) rename in a short low-traffic window with Heroku maintenance mode, both renames in one transaction under a short lock_timeout, then deploy code using plain status; (7) drop legacy_status later. Steps 1 to 4 and the report are labelled live-safe; step 6 is labelled low-traffic window; each step has its rollback and a backup is captured before step 6.
- Req 42: SOLUTION.md describes the new-column approach as plan only; it states that rows written during the backfill are covered by writing both columns before the backfill starts and by a final catch-up pass before the switch; it states that raw SQL that names the status column (dashboard, export, status select) lives in one place so the switch changes it once; no migration or backfill execution is in the repo.
- Req 43: SOLUTION.md names for each step its lock behaviour and mitigation: short lock_timeout with retry on the column add, the rename and the later drop; row-id batches with a throttle; pause thresholds of replication lag over 5 seconds, any lock wait over 2 seconds, or request latency over 1.5 times baseline; no long transactions; any index on the new column built CONCURRENTLY; verification counts run off the primary or on a partial index; statement_timeout on the backfill.

## Definition of done
- PR links this ticket (`TKT-11` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
- 2026-11-07 implementation: `bin/rails statuses:report` (`StatusReport`, read-only, id batches, distinct stored values with count and latest updated_at, free-looking text described by length only, no ids or employee data), `StatusMapping` and a draft `db/status_mapping.yml` (approved: false), two guard tests (raw status SQL only in `StatusOptions::NORMALISED_SQL`; no application path updates historical statuses). The plan is `assessment-log/solution-drafts/status-backfill.md` (merged into SOLUTION.md by TKT-12). 202 runs, 0 failures; rubocop, brakeman, bundler-audit clean. No migration, nothing executed.
- 2026-11-07 measurements: report on the 500k seed 4.7 s, 14 distinct values, totals equal SQL (500,000; 13 non-null values plus NULL); the draft maps 446,246 rows, 53,754 stay unmapped. Rehearsal on a throwaway copy (dropped afterwards): add column 0.9 ms (a held lock made `lock_timeout` 1 s give up after 1.005 s), 100 batches of 5,000 ids median 60 ms and 5.7 s in total, rerun touches 0 rows, table grew 294 to 541 MB with 443k dead rows (only 3,434 HOT updates), verification count about 65 ms with or without a partial index, both renames under 0.5 ms each.

