---
key: TKT-10
type: Task
title: Task 3: status validation, default, cut-over date switch, dropdown
status: Done
parent: EPIC-1
updated: 2026-11-07T08:28:15Z
---

## Description
**Context:** New and updated records must use only the five canonical statuses. Stop the bad data first, on the Ruby side, after a cut-over date assessors have been told about.

**Scope:** Validation allowing only pending, in_progress, completed, needs_follow_up, archived on create and when status changes (no alias mapping on write); default `pending` for a new assessment without one; a configured cut-over date: before it, a log line counting would-be rejections with no values; on and after it, rejection; the screen's free text replaced by a five-value dropdown that cannot be saved empty.

**Not in scope:** A database constraint (Req 30 dropped), mapping legacy values, backfill, the change request document itself (outlined in TKT-11/TKT-12).

**Depends on:** TKT-9

**Spec requirements:** Req 29, Req 40, Req 41, Req 44 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- Validation must not run when status is unchanged, otherwise any update to a legacy row with a dirty status fails.
- Test both sides of the cut-over date.

## Acceptance criteria
- Req 29: Canonical values are pending, in_progress, completed, needs_follow_up, archived; saving a record with any other value (including case or whitespace variants of them) fails validation with a clear message; the check runs only when status is being set, so updating another field on a legacy row with a dirty status still succeeds; there is no alias mapping on write.
- Req 40: SOLUTION.md outlines the change request (what changes, the dropdown, the cut-over date, who to contact); a configured cut-over date makes Req 29 log a count of would-be rejections with no values before the date and reject on and after it; a test covers both sides of the date.
- Req 41: One form edits an assessment's status for signed-in admins of its company (existing sign-in, no new role); the baseline version offers a free-text field; the later version offers a dropdown of the five values that cannot be saved empty, with server-side validation from Req 29; both versions are visible in git history.
- Req 44: Creating an assessment with no status stores pending; creating one with a non-canonical status fails validation (Req 29); a test covers both.

## Definition of done
- PR links this ticket (`TKT-10` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
- 2026-11-07 implementation: `Assessment::STATUSES`, default `pending` for nil on create, status validation only when the status is being set, date switch via `STATUS_CUTOVER_DATE` (`config.x.status_cutover_date`; unset enforces; invalid stops boot), one count log line per would-be rejection (per-process count, no value), the TKT-9 screen is now a five-option dropdown that always refuses other values. The free-text version stays in git history (TKT-9). Test helper `create_assessment` saves legacy rows with `validate: false`. 178 runs, 0 failures; rubocop, brakeman, bundler-audit clean. Manual checks on the dev server (curl, cut-over 2099): five options and no text field, empty and free-text submits 422, valid submit saved, console count line seen once. Historical rows are not touched here (the backfill is only designed, in TKT-11).

