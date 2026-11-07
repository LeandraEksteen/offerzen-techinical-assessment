# TKT-10 plan: status validation, default, cut-over date switch, dropdown

Status: approved and built. Source ticket: `assessment-log/tickets/TKT-10.md`. Spec: `assessment-log/spec/` (Req 29, 40, 41, 44). Decisions this builds on: D-018 (Task 3 approach), D-027 (the free-text baseline), the T3-E and T3-I answers (dropdown live before the date, the page cannot be saved empty).

Epic tree read: EPIC-1 children TKT-1 to TKT-9 merged; TKT-10 (this), TKT-11, TKT-12 To Do. No comments on TKT-10.

## Why this matters
Ten years of free text gave the table "Complete ", "comp", "done" and blanks. The first thing to do is stop new bad values arriving, before cleaning old ones (TKT-11 plans that). Assessors are told in a change request that on a given date only five statuses are accepted; until then the app only counts what it would have rejected, so ops can see how many writers still send old values before anything breaks. The dropdown (the "after" half of Req 41) makes the right value the easy one.

## Architecture overview
Validation lives on `Assessment` and runs only when the status is being set (new record or changed status), so an update to another field on a legacy row with a dirty status still works. A configured date decides what a failure means: before it the row saves and one log line counts it; on and after it the save fails with a clear message. The TKT-9 screen swaps its text field for a select of the five values and, regardless of the date, refuses anything else (the dropdown is already live before the date, so an empty or hand-crafted value is never saved from it). Call path: dashboard row, GET edit (select), PATCH update (screen check, then model validation), redirect.

## Requirements
- Req 29: five canonical values; non-canonical (case and whitespace variants too) fails with a clear message on create and when status changes; unchanged status is never validated; no alias mapping.
- Req 40 (code half): configured cut-over date; before it a count log line with no values; on and after it rejection; a test on both sides. The SOLUTION.md change-request outline is TKT-12's.
- Req 41 (second half): dropdown of the five values that cannot be saved empty, server-side validation; free-text version stays in history (TKT-9).
- Req 44: creating with no status stores pending; creating with a non-canonical status fails.

## Evidence from the code (read on origin/main)
- `Assessment` is deliberately unvalidated for status (`app/models/assessment.rb`); the seeder writes with `Assessment.insert_all`, which skips validations and callbacks, so seeded dirty rows are unaffected.
- `AssessmentsController` (TKT-9) selects only ids, date and status and uses `update!` with the typed text; its tests assert free text is stored, so they change to the dropdown rules.
- About 40 test lines create assessments with legacy statuses (`"done"`, `"Complete"`, `nil`, `""`, `" n/a "`) through `create_assessment`/`Assessment.create!`. They would all fail validation or have `nil` turned into `pending`. The helper must write legacy rows with `save!(validate: false)` (skips the default as well, so `nil` stays `nil`).
- No `config.x` or ENV configuration exists yet; `config/application.rb` is where the log formatter is already configured.
- `StatusOptions.forget(company)` (TKT-9) already refreshes the filter list after a save.

## Changes required (single repo)

| File | Change | Complexity |
|---|---|---|
| `app/models/assessment.rb` | `STATUSES` constant; `before_validation :default_status, on: :create` (nil only); `validate :status_is_canonical, if: :status_being_set?`; before the cut-over date a failure is not an error: log a count line and keep a per-process counter; remove the "deliberately unvalidated" comment for status | Medium |
| `config/application.rb` | `config.x.status_cutover_date` parsed from `ENV["STATUS_CUTOVER_DATE"]` (ISO date; unset = nil = enforce; invalid = raise at boot with a clear message) | Low |
| `app/controllers/assessments_controller.rb` | Permit only the five values (always), else re-render 422 with a message; keep tenancy, forget-cache and redirect | Low |
| `app/views/assessments/edit.html.erb` | Select of the five values with humanised labels, a "Choose a status" prompt that cannot be submitted (`required`, no blank option), the legacy value shown as a note | Low |
| `test/test_helper.rb` | `create_assessment` saves with `validate: false` and skips the default (legacy rows) | Low |
| `test/models/assessment_test.rb`, `test/controllers/assessments_controller_test.rb` | The matrix below; TKT-9 free-text tests rewritten | Medium |
| `assessment-log/` | Ticket, D-028, prompts, plan state | Low |

No migration, no gem, no JavaScript.

## Contract summary
None. Single-repo change; see `contract.md`.

## PR strategy
One PR, base `main`, branch `feat/TKT-10/status-validation`, title `TKT-10 | Task 3: status validation, default, cut-over date switch, dropdown`. Yaml in `pr-strategy.yaml`.

## Test matrix

| ID | Req | Case | Type | Bucket | PR |
|---|---|---|---|---|---|
| UT-1 | 29 | The five values save on create and on change | positive | unit | 1 |
| UT-2 | 29 | Case, whitespace, unknown and blank values fail with a clear message | negative | unit | 1 |
| UT-3 | 29 | Updating another field on a legacy-dirty row succeeds | edge | unit | 1 |
| UT-4 | 29 | Dirty to dirty fails; dirty to canonical succeeds | edge | unit | 1 |
| UT-5 | 44 | Create with no status stores pending | positive | unit | 1 |
| UT-6 | 44 | Create with non-canonical (including empty string) fails | negative | unit | 1 |
| UT-7 | 40 | Before the date: saves, one count line, no value in it | positive | unit | 1 |
| UT-8 | 40 | On and after the date: rejected, no count line | positive | unit | 1 |
| UT-9 | 40 | Day before and day of; unset enforces; invalid config fails at boot | edge | unit | 1 |
| UT-10 | 41 | Select of five, no text field, no selectable blank, legacy value as a note | positive | unit | 1 |
| UT-11 | 41 | Choosing a value saves, redirects, forgets the cached list | positive | unit | 1 |
| UT-12 | 41 | Empty, missing or non-canonical refused by the screen, before and after the date | negative | unit | 1 |
| UT-13 | 41 | Other company 404, signed out redirected | negative | unit | 1 |
| UT-14 | 29, 40 | Count line and message hold no status value and no email | edge | unit | 1 |
| MC-1 | 40 | Dev server, future date: count line appears for a would-be rejection, no values in the log | positive | manual | 1 |
| MC-2 | 41 | Dev server: dropdown with five options, legacy row asks for a choice, hand-crafted empty refused | positive | manual | 1 |

## Risks and mitigations
- **Existing tests hold legacy statuses.** About 40 usages would fail or change. Mitigation: the helper writes legacy rows with `validate: false`; the validation tests use real `create`/`update`. The suite must pass with no other change.
- **Other writers bypass validation:** the seeder (`insert_all`, intentional: the benchmarks and the status report need dirty data), `update_all`, `update_columns`, console and the later backfill. Decision: accept and note; they are the legacy and migration paths, not user input. The ticket scope has no database constraint (Req 30 dropped).
- **"Unset means enforce" is a choice** (open question 1): a deploy with no date set rejects at once. Mitigation: the deploy note, and the change request goes out first.
- **Count is per process** and resets on restart; with several web processes the log lines add up. It is an indication (T3-G said approximate is fine), not an audit.
- **Date comparison** uses the app's time zone (`Date.current`, UTC by default); the date is inclusive ("on and after"). UT-9 pins both sides.
- **Log hygiene:** the count line has no value, no id, no email (UT-14). The error message names the five allowed values, not the submitted one.
- **A legacy row cannot be shown "as selected" in a dropdown** and a naive select would pre-select the first option, silently turning an old value into `pending` on Save. Mitigation: a "Choose a status" prompt that must be changed (required) and the old value shown as a note.
- **Partial select (TKT-9):** validation reads only `status`, and the status check must not touch unloaded columns. UT-3 uses a partially loaded record.
- **Invariant writers:** the one invariant is "new and changed statuses are canonical after the date"; writers listed above, all decided "accept".

## Open questions (need your decision; recommendation first)
1. **Cut-over date setting and the unset case.** Recommend `STATUS_CUTOVER_DATE` (ISO date) read once at boot; unset means enforce now (the end state is the default; the date only delays it); an invalid value fails boot loudly. Alternative: unset means count-only. Accept?
2. **Screen versus model.** Recommend the screen always refuses anything but the five values (the dropdown is already live and the page "obviously can't be saved without an input"), while the model's rejection follows the date for every other writer. Accept?
3. **The count line.** Recommend one log line per would-be rejection with a running per-process count and no value, for example `status validation: would reject after cut-over (count=3)`. Alternative: a periodic summary. Accept?
4. **Blank string on create.** Recommend only `nil` becomes `pending`; an empty string is non-canonical and fails (Req 44 says "no status", the dropdown cannot send blank, and `""` is one of the legacy dirty values we must stop). Accept?
5. **Legacy value on the form.** Recommend a "Choose a status" prompt (required, not a selectable value) plus a note "Current value: X (not a standard status)" when the stored value is not one of the five. Alternative: pre-select `pending`. Accept?
6. **Test helper.** Recommend `create_assessment` saves with `validate: false` (legacy rows are real in this table). Alternative: set the test cut-over date in the future. Accept the helper change?
7. **Dropdown labels.** Recommend human labels (Pending, In progress, Completed, Needs follow-up, Archived) with the canonical value as the option value. Accept?

## Out of scope
Database constraint (Req 30 dropped), alias mapping on write, mapping legacy values, backfill, the status report, the change request document (outlined in TKT-11/12), README and final write-up.

## Estimated scope
About 7 files and 250 lines including tests. Single PR.

## Critic pass
Not run as a separate agent: single repo, no contract items.

## Self-check
- Req 29, 40 (code half), 41 (second half) and 44 land in PR 1 with UT-1 to UT-14 and two manual rows; the SOLUTION.md part of Req 40 is TKT-12's and is named in the ticket's scope.
- If open question 1 is answered "unset means count-only", UT-9's unset case flips.

## Implementation notes (added after building)
- Built as planned; every open-question recommendation was accepted. The user added: take into account the requirement to design, but not fully execute, a plan to bring historical records into alignment. In this PR that means: no historical row is changed (no migration, no data task), legacy values stay readable and editable, and nothing here blocks the backfill. `Assessment::STATUSES` is the one list TKT-11's report and mapping will reuse; the validation runs only on a changed status, and the backfill writes through SQL or `update_all`, so it will not trip the validation or touch `updated_at` semantics by accident. The backfill design itself (report, mapping file, batches, cut-over, rollback) is TKT-11 and TKT-12.
- Labels come from `String#humanize`, so "Needs follow up" (no hyphen), not "Needs follow-up" as the plan wrote.
- Tests that create legacy statuses now go through `legacy_assessment` / `create_assessment` (`save!(validate: false)`); `StatusOptionsTest` uses `update_columns` for the same reason.
- A would-be rejection is logged at info level by `Rails.logger`; the Rails SQL debug log (development only) still prints the saved status value in the INSERT, which was already true before this ticket.
- Manual checks (curl, cut-over date 2099): five options, no text field, empty and free-text submits 422, valid submit saved, count line logged once from a console write. Side effect: the console check overwrote the status of the lowest-id dev assessment, which was restored to `archived` but not to its seeded value; re-seed the dev database if exact seeded values matter (it does not touch the page-1 snapshot rows).

