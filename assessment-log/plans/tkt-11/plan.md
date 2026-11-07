# TKT-11 plan: status report and the backfill, release and rollback plan

Status: approved and built. Source ticket: `assessment-log/tickets/TKT-11.md`. Spec: `assessment-log/spec/` (Req 31, 32, 33, 34, 42, 43; the document half of Req 40 rides along). Decisions this builds on: D-018 (Task 3 approach), D-028 (the status rule and cut-over date).

Epic tree read: EPIC-1 children TKT-1 to TKT-10 merged; TKT-11 (this) and TKT-12 To Do. No comments on TKT-11.

## Why this matters
After TKT-10 no new bad status gets in (once the cut-over date passes), but the table still holds ten years of "Complete ", "comp", "done" and blanks, and the brief asks for a plan, not an execution, to bring those historical rows into line. The brief's two constraints decide the shape: keep the app responsive, and never lock or stall the large `assessments` table. This ticket delivers (a) a read-only report so people can see exactly which stored values exist and how a proposed mapping would land, and (b) the written, step-by-step release and rollback plan for a Heroku-like host. Nothing in the repo changes a historical row.

## Architecture overview
Two small read-only classes plus a rake task, and one document. `StatusReport` reads the table in id batches and counts distinct stored values (with the latest `updated_at`); `StatusMapping` loads the versioned mapping file (`db/status_mapping.yml`, a draft until assessors approve it) and normalises values the same way `StatusOptions` does, so the report can show mapped counts per canonical status and the unmapped remainder. The plan document (`assessment-log/solution-drafts/status-backfill.md`, merged into SOLUTION.md by TKT-12) describes: the sheet and the mapping file, the change request, the new nullable column with dual-write and a single owner of its name, the seven steps with live-safe and low-traffic labels, backup and recovery, and lock and responsiveness safeguards. Call path of the report: rake task, `StatusReport` batches by id, optional `StatusMapping`, printed text.

## Requirements
- Req 31: sheet of distinct values only (count, latest updated_at, never rows or ids, scanned for free text first), assessor confirmation, versioned mapping file used by the backfill, draft aliases are a starting guess, an unmapped value stays NULL and blocks the switch.
- Req 32: the legacy column keeps receiving the canonical value after the alias switch until dropped; rollback is a code deploy before the rename and the reverse rename after it; `pg:backups:capture` immediately before the rename; restore is the last resort.
- Req 33: a rake task reads in batches without writing and prints one row per distinct stored value with a count and latest updated_at; with a mapping file it also prints counts per mapped result and the number of unmapped values; no code path updates historical statuses.
- Req 34: the seven ordered steps with labels, rollbacks and a backup before step 6.
- Req 42: new-column approach is plan only; rows written during the backfill are covered by dual-write first and a final catch-up pass; raw SQL naming the status column is in one place; no migration or backfill execution in the repo.
- Req 43: per step lock behaviour and mitigation; short `lock_timeout` with retry; id batches with a throttle; pause thresholds (replication lag over 5 s, any lock wait over 2 s, latency over 1.5 times baseline); no long transactions; any index on the new column CONCURRENTLY; verification counts off the primary or on a partial index; `statement_timeout` on the backfill.

## Evidence from the code (read on origin/main)
- `StatusOptions::NORMALISED_SQL` (`NULLIF(lower(btrim(status, E' \t\r\n')), '')`) is the one raw SQL string that names the column; `Assessment.matching` uses it through `StatusOptions.condition`. Dashboard and export read `status` through ActiveRecord attributes (`select(:status)`, `pluck(:status)`), which resolve attribute aliases, so a future `alias_attribute :status, :status_canonical` only needs the one raw SQL constant changed (inferred from Rails behaviour, to be proven by a test in the switch PR and by MC-2).
- The seeder writes the dirty variants with `insert_all` (`lib/assessment_seeder.rb`): nil, empty, blank, "n/a", complete, "Complete ", COMPLETE, comp, done, Done, plus the five canonical values. Good realistic input for the report and the draft mapping.
- `lib/score_report.rb` and `lib/tasks/dashboard.rake` are the analog: a read-only class batching by id, printed output, a test that nothing is written.
- `Assessment` after TKT-10 rejects non-canonical values only when the status is being set, so a backfill that writes through SQL or `update_all` is the legitimate bypass and will not trip the validation.
- The `assessments` table has one secondary index (company_id, assessment_date); there is no status index and none is wanted on the old column (D-017).

## The plan document in outline (the main deliverable)
`assessment-log/solution-drafts/status-backfill.md`, written in plain steps. It must contain:
1. **Order of events:** change request first, cut-over date passes (TKT-10 rejects new bad values), dual-write goes live, mapping approved, backfill, verify, switch, rename, drop. Why that order.
2. **The sheet and the mapping file:** only distinct values with row count and latest `updated_at` (from `statuses:report`), never rows or ids, scanned for free text first; assessors confirm doubtful values; the approved result is committed as `db/status_mapping.yml` (version, approved flag, who and when) and is the only input to the backfill; the draft aliases are a starting guess; a value with no approved mapping stays NULL and blocks the switch (NULL, empty and blank-only rows included: they need an approved target too).
3. **The change request** (what changes, the dropdown, the cut-over date, who to contact, what happens to old records, what integrations that post free text must do).
4. **The new column:** nullable `status_canonical` (placeholder name), dual-write from the first deploy (new column gets the mapped canonical value, legacy column keeps the stored value, and after the cut-over date both equal the canonical one), one owner of the column name in code, rows written during the backfill covered by dual-write plus a final catch-up pass (`WHERE status_canonical IS NULL` and rows whose `updated_at` is after the backfill started), the one raw-SQL constant that changes at the switch.
5. **The seven steps** (each with label, what it does, lock behaviour and mitigation, verification, rollback):
   1. Add the nullable column (live-safe; catalog-only change, but it needs a very short ACCESS EXCLUSIVE lock: `lock_timeout` of about 2 s with retry; no default, so no rewrite) and deploy code that writes both columns. Rollback: deploy the previous release; the empty column is harmless; drop it later.
   2. Backfill in batches of about 5,000 ids from a one-off dyno (live-safe): `UPDATE ... WHERE id BETWEEN a AND b AND status_canonical IS NULL` from the approved mapping, each batch its own short transaction, `statement_timeout` and `lock_timeout` set per batch, a throttle (sleep in proportion to the batch time), resumable from a printed last id, idempotent (re-running only fills what is still NULL), paused when a threshold trips (replication lag over 5 s, any lock wait over 2 s, request latency over 1.5 times baseline). Rollback: stop the job; set the column back to NULL in id batches if ever needed; nothing reads it yet.
   3. Verify (live-safe): zero rows with the new column NULL where a mapping exists, zero unmapped values, counts per canonical status match the report's mapped counts; counts run on a follower or use a partial index `... WHERE status_canonical IS NULL` built CONCURRENTLY (dropped after step 4). Rollback: none needed; do not proceed.
   4. Switch the app to the new column with an alias (live-safe, one deploy): `alias_attribute :status, :status_canonical`, the raw SQL constant changed once, the final catch-up pass run first. Rollback: deploy the previous release (the legacy column was kept written).
   5. Keep writing the legacy column (live-safe): the canonical value, so anything still reading it and the reverse rename stay valid until the drop. Rollback: n/a.
   6. Rename in a short low-traffic window with Heroku maintenance mode: `pg:backups:capture` immediately before, then both renames in one transaction under a short `lock_timeout` (old `status` to `legacy_status`, `status_canonical` to `status`), then deploy code that uses plain `status` and restart all dynos (Rails caches column names, so dynos running the old code break after the rename; maintenance mode covers that gap). Rollback: before the rename, a code deploy; after it, the reverse rename in one transaction plus the previous release. Restoring the backup is the last resort because it loses every later write.
   7. Drop `legacy_status` later (low-traffic window; a short `lock_timeout` with retry; take a backup first; irreversible, so only after a quiet period). Rollback: restore the backup column data only from the backup.
6. **Backup and recovery on a Heroku-like host:** `heroku pg:backups:capture --app <app>` and `heroku pg:backups:info`, `heroku pg:backups:restore <backup> DATABASE_URL --app <app> --confirm <app>` as the last resort, and a rehearsal of the whole sequence on a copy first (`heroku pg:copy` to staging).
7. **Responsiveness and lock safeguards table** (Req 43): one row per step with its lock, the longest it can hold it, the mitigation, and the pause thresholds.
8. **What is not done here and why:** nothing is executed; no migration or backfill code is in the repo; the assessor-side front end and API changes outside this repo are only described.

## Changes required (single repo)

| File | Change | Complexity |
|---|---|---|
| `lib/status_report.rb` (new) | Read-only, batched by id; one row per distinct stored value (count, latest `updated_at`); free-looking text described by length; optional mapping section | Medium |
| `lib/status_mapping.rb` (new) | Loads and validates `db/status_mapping.yml`; normalises like `StatusOptions`; `draft?`, `target_for(value)` | Low |
| `db/status_mapping.yml` (new) | Draft (`approved: false`, version 0): the author's draft aliases; NULL, empty, blank and "n/a" deliberately unmapped | Low |
| `lib/tasks/statuses.rake` (new) | `statuses:report` (BATCH env) | Low |
| `test/lib/status_report_test.rb`, `status_mapping_test.rb`, `status_guards_test.rb` (new) | The matrix below | Medium |
| `assessment-log/solution-drafts/status-backfill.md` (new) | The plan document | High (the main deliverable) |
| `assessment-log/` | Ticket, D-029, prompts, benchmarks note (rehearsal numbers), plan state | Low |

No migration, no gem, no application behaviour change.

## Contract summary
None. Single-repo change; see `contract.md`.

## PR strategy
One PR, base `main`, branch `feat/TKT-11/status-report-backfill-plan`, title `TKT-11 | Task 3: status report and the backfill, release and rollback plan`. Yaml in `pr-strategy.yaml`.

## Test matrix

| ID | Req | Case | Type | Bucket | PR |
|---|---|---|---|---|---|
| UT-1 | 33 | One row per distinct stored value with count and latest updated_at; variants kept apart | positive | unit | 1 |
| UT-2 | 33 | NULL, empty and blank-only are separate labelled rows | edge | unit | 1 |
| UT-3 | 33 | Read-only: no writes, no DDL, nothing changes | negative | unit | 1 |
| UT-4 | 33 | Batching gives the same totals as one pass | edge | unit | 1 |
| UT-5 | 31 | Free-looking text and emails never printed; no ids or employee data | negative | unit | 1 |
| UT-6 | 33, 31 | With a mapping: rows per mapped status plus unmapped values and rows; without: says so | positive | unit | 1 |
| UT-7 | 31 | Loader normalises like StatusOptions, rejects bad targets and duplicates, labels a draft | edge | unit | 1 |
| UT-8 | 31 | The committed draft file loads; targets canonical | edge | unit | 1 |
| UT-9 | 42 | Raw SQL naming the status column only in `StatusOptions::NORMALISED_SQL` | negative | unit | 1 |
| UT-10 | 33, 42 | No application path updates historical statuses; no new migration touches status | negative | unit | 1 |
| MC-1 | 33 | 500k seed: totals equal SQL GROUP BY, runtime, no free text or ids | positive | manual | 1 |
| MC-2 | 34, 43 | Throwaway copy: lock and timing numbers for the steps, recorded in the plan | positive | manual | 1 |
| MC-3 | 31, 32, 34, 42, 43 | Document read against the requirements | positive | manual | 1 |

Req 32 and the document halves of Req 31, 34, 42 and 43 are asserted by MC-3 (a document cannot be unit-tested); the code halves by UT-1 to UT-10.

## Risks and mitigations
- **The report prints stored values, which could be free text or personal data.** Mitigation: values go through `Pii::Scrubber`; anything longer than 40 characters or with more than 4 words is printed only as `[text, N characters]` and flagged; no ids, rows or emails; the sheet is built from this output only after a human scans it (Req 31). UT-5.
- **A read of the whole table on a live system.** Mitigation: batches by id (copying `ScoreReport`), run off-peak or on a follower; the output is a grouped count, not rows. MC-1 records the runtime.
- **The plan names the Rails column cache problem at the rename** (old dynos know the old column names). Mitigation: maintenance mode, both renames in one transaction, immediate deploy and restart. Alternatives considered and not chosen: a view over the table (more moving parts), `ignored_columns` (does not cover the writes of old code).
- **Dual-write drift:** a legacy writer that bypasses the model (console, scripts, another app) could write the old column only. Mitigation: the final catch-up pass before the switch and the verification counts; noted in the document.
- **The mapping file is the single input of an irreversible-looking step.** Mitigation: `approved: false` until assessors sign off, version and approver recorded, the (future) backfill refuses an unapproved file; unmapped rows stay NULL and block the switch.
- **The draft aliases are guesses** (`comp`, `done`): labelled a draft everywhere, the report shows what each would do.
- **"Nothing executed" must stay true.** Mitigation: UT-9 and UT-10 guard it; no migration in the PR; the rehearsal (MC-2) runs on a throwaway copy of the dev database and only its numbers are recorded.
- **Invariant writers:** the invariants are "new column equals mapped legacy value" and "legacy column equals canonical after the cut-over". Other writers (seeder `insert_all`, `update_all`, console, a future import, data masking) bypass the model; decisions: seeder accept (it is test data in development only), others covered by the catch-up pass and verification counts, noted in the document.

## Open questions (need your decision; recommendation first)
1. **Where the plan lives.** Recommend `assessment-log/solution-drafts/status-backfill.md` now (like the score-reader draft), merged into SOLUTION.md by TKT-12. Accept?
2. **A draft mapping file in the repo.** Recommend `db/status_mapping.yml` with `approved: false`, version 0, your draft aliases (complete, comp, done, finished to completed; in progress to in_progress; and so on), and NULL, empty, blank and "n/a" deliberately unmapped so assessors must decide them (Req 31). The report shows its effect on the seed. Alternative: no file, only a sample in the document. Accept the file?
3. **What the report prints.** Recommend every distinct value as stored with whitespace made visible, emails scrubbed, and values over 40 characters or over 4 words described only as `[text, N characters]` with a flag. Accept?
4. **The new column's name and its single owner.** Recommend the placeholder name `status_canonical`, owned by one constant in `Assessment` in the future dual-write PR (not built now), plus the existing `NORMALISED_SQL` constant. Accept the name?
5. **Rehearsal numbers.** Recommend a throwaway copy of the 500k dev database to time add-column (lock), a 5,000-row batch update, the partial index CONCURRENTLY, the verification count with and without it, and the two renames, recording only the numbers in the document (MC-2). Alternative: no numbers, reasoning only. Accept?
6. **Two guard tests** (raw SQL in one place; no code updates historical statuses, with the seeder allowed). Accept?
7. **NULL, empty and blank-only rows** also need an approved target before the switch (probably `pending`, but that is the assessors' call; the plan assumes nothing). Accept?
8. **Rename mechanics** as agreed (maintenance mode, both renames in one transaction, immediate deploy and restart, backup right before). Accept as written?

## Out of scope
Executing any migration or backfill, a database constraint (Req 30), the assessor-side front end and API changes outside this repo (described only), the README and final SOLUTION.md assembly (TKT-12), the change request as a standalone file beyond its outline.

## Estimated scope
About 8 files and 450 lines of code and tests, plus the plan document (about 250 lines). Single PR.

## Critic pass
Not run as a separate agent: single repo, no contract items.

## Self-check
- Req 33's code parts and Req 31's report parts land in PR 1 with UT-1 to UT-10; the document parts of Req 31, 32, 34, 42 and 43 land as the plan document, checked by MC-3. TKT-12 moves the document into SOLUTION.md.
- If open question 2 is answered "no file", UT-6 and UT-8 shrink to a fixture file in the tests.

## Implementation notes (added after building)
- Built as planned; every open-question recommendation was accepted, including the rehearsal (MC-2) and the two guard tests.
- The guard for raw SQL is a heuristic: it looks for the column named inside a quoted SQL string and ignores comments. A mutation check (a temporary file with `"status = ?"` and an `update_all` on assessments) made both guards fail and was then removed. UT-10 is line level: a bulk writer is only an offender when the same line names assessments or the status (ExportRequest bookkeeping and EXPLAIN are not historical data).
- MC-2 numbers changed the plan document's advice: the partial index did not speed the verification count at 500k rows (about 65 ms either way), so it is optional; and the backfill is write-heavy (443k dead rows, 294 to 541 MB, almost no HOT updates), which is why the throttle, off-peak scheduling and vacuum notes are in the document. Not measured: WAL volume, autovacuum under load, the lock queue forming behind a waiting ALTER (documented PostgreSQL behaviour).
- The report prints blank-only values as `(blank only, N characters)`; the rake task is `statuses:report` (BATCH env).
- MC-3 (reading the document against Req 31, 32, 34, 42, 43) was done by checking each requirement's acceptance text against the document's sections: sheet and mapping file, dual-write and one owner, seven steps with labels, lock notes and rollbacks, backup before the rename, thresholds, statement_timeout, CONCURRENTLY, follower or partial index.

