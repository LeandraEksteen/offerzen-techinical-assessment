# SOLUTION.md draft: bringing historical statuses into line (TKT-10, TKT-11)

Draft section, merged into SOLUTION.md by TKT-12. **This is a plan. Nothing in the repository changes a historical row**: there is no migration and no backfill code, and two guard tests (`test/lib/status_guards_test.rb`) keep it that way. Code that exists: the write-side rule (`Assessment`, TKT-10), the read-only report (`bin/rails statuses:report`, `lib/status_report.rb`) and the draft mapping file (`db/status_mapping.yml`, `lib/status_mapping.rb`).

## The problem and the two constraints

The `assessments` table holds ten years of free-text statuses: `Complete `, `COMPLETE`, `comp`, `done`, `n/a`, empty, blank, NULL. The brief asks for a plan to bring the historical rows into line with the five canonical statuses (`pending`, `in_progress`, `completed`, `needs_follow_up`, `archived`), under two constraints: **keep the app responsive throughout** and **avoid changes that would lock or stall the large table**. Every step below is judged against those two.

## Order of events, and why

1. **Stop the bad data first (done, TKT-10).** Ruby rejects any non-canonical status on create and when a status changes, from a configured cut-over date (`STATUS_CUTOVER_DATE`); before that date it only logs a count of would-be rejections. The assessor screen is a five-option dropdown. There is no alias mapping on write and no database constraint: the database is not responsible for this rule.
2. **Change request goes out before the date** (outline below).
3. **The cut-over date passes.** From then no new dirty value arrives, so the set of historical values stops growing.
4. **Dual-write goes live** (step 1 below) before any backfill, so rows written meanwhile are already covered.
5. **Mapping approved** by assessors (sheet and mapping file below).
6. **Backfill, verify, switch, rename, later drop** (the seven steps).

Cleaning old rows before stopping new dirty ones would be a treadmill; that is why the order is fixed.

## The sheet and the versioned mapping file (Req 31)

- **The sheet.** `bin/rails statuses:report` prints one row per distinct status value as stored with a row count and the latest `updated_at`. That output is what goes into a shared sheet: **only distinct values with counts and a date, never rows or ids**. The status column is free text, so a value could be anything; the report scrubs emails and describes anything that looks like free text (over 40 characters or over 4 words) only as `[text, N characters]` with a REVIEW flag, and a human scans the output before it is shared. On the 500k seed it prints 14 rows in 4.7 seconds (`assessment-log/benchmarks/status-report-500k-seed.txt`).
- **Assessors confirm the doubtful values** (`n/a`, empty, blank, anything unfamiliar). Where in doubt we pull the assessors in; nothing is guessed.
- **The versioned mapping file.** The approved result is committed as `db/status_mapping.yml`: `version`, `approved`, `approved_by`, `approved_on`, and `mapping` from the normalised stored value (trimmed, lower-cased, the same normalisation `StatusOptions` uses; `__none__` for NULL, empty and blank-only) to one of the five. It is the only input the backfill uses, and the backfill refuses a file that is not approved. The file in the repo is a **draft**: the author's starting-guess aliases (`complete`, `comp`, `done`, `finished` to `completed`, and so on), with `approved: false`. NULL, empty, blank-only and `n/a` are deliberately left unmapped.
- **A value without an approved mapping stays NULL in the new column and blocks the switch.** That includes NULL, empty and blank-only rows: they need an approved target too (probably `pending`, but that is the assessors' decision, not an assumption of this plan).
- `statuses:report` also shows, once a mapping file exists, rows per mapped status and the number of unmapped values and rows. On the draft against the 500k seed: 446,246 rows would map, 53,754 rows in 4 distinct values would not.

## The change request (outline)

What goes to assessors and to anyone whose system writes statuses, before the cut-over date:

- **What changes:** the status field becomes a dropdown of five values (Pending, In progress, Completed, Needs follow up, Archived). Free text and the old spellings are no longer accepted.
- **When:** the cut-over date. Until then the app accepts the old values but counts them, so the date can be moved if too many writers still send them.
- **Who must act:** assessors (pick from the list); owners of any import, integration or script that writes statuses (send one of the five exact values; `Complete ` or `done` will be rejected from the date).
- **What happens to old records:** nothing at first. They keep their old text and stay editable; a later, separate step (this plan) maps them to the five values.
- **Who to contact:** the product owner and the engineering owner for the assessments module (names go in the real document).

## The new column, dual-write and a single owner of the name (Req 42)

- **Approach (plan only):** add a new nullable column (placeholder name `status_canonical`), fill it from the approved mapping, switch the app to it with an alias, then rename the old column to `legacy_status` and the new one to `status`. The rename is done later, in a quiet window, to avoid permanent technical debt and because other readers of the table exist.
- **Dual-write from the first deploy:** the model writes both columns. The new column gets the canonical value (after the cut-over date that is the status itself; before it, the mapped value or NULL). The legacy column keeps receiving the status.
- **Rows written during the backfill** are covered because dual-write is live before the backfill starts, and by a **final catch-up pass** before the switch (rows where the new column is still NULL and a mapping exists, plus any row whose `updated_at` is after the backfill started).
- **One owner of the name.** Raw SQL that names the status column lives in one place, `StatusOptions::NORMALISED_SQL` (used by the dashboard filter, the export filter and the status list); a guard test fails if a second place appears. Everything else reads `status` through ActiveRecord attributes. At the switch, `alias_attribute :status, :status_canonical` plus changing that one constant is the whole code change. (Rails resolves attribute aliases in `select` and `pluck`; to be proven by a test in the switch PR.)
- **Other writers** that bypass the model (console, scripts, another app, the seeder in development) can write only the old column. The catch-up pass and the verification counts exist to catch them.

## The seven steps (Req 34)

Each step says whether it is **live-safe** (runs with the app serving traffic) or needs the **low-traffic window**, what lock it takes, and how to roll it back. Rehearsal numbers are from a throwaway copy of the 500k-row development database (294 MB with indexes), PostgreSQL 16, local machine; production will be slower and must be re-measured on staging first.

| # | Step | Label | Lock behaviour and mitigation | Rollback |
|---|---|---|---|---|
| 1 | Add the nullable column `status_canonical` (no default) and deploy code that writes both columns | live-safe | Adding a nullable column without a default is a catalog change, no table rewrite (0.9 ms here). It still needs an ACCESS EXCLUSIVE lock for an instant, and a statement waiting for that lock makes every later query on the table queue behind it. So: `SET lock_timeout = '2s'` and retry; with a long transaction holding the table the statement gave up after 1.005 s and changed nothing. Run it from the release phase. | Deploy the previous release. The empty column is harmless; drop it later. |
| 2 | Backfill in batches of about 5,000 ids from a one-off dyno | live-safe | See "Backfill design" below. | Stop the job. The column is not read yet; if ever needed, set it back to NULL in id batches. |
| 3 | Verify: 100% filled where a mapping exists, no unmapped values, counts per status equal the report's mapped counts | live-safe | One count per check. Run on a follower or off-peak. At 500k rows the count takes about 65 ms; a partial index (`WHERE status_canonical IS NULL`, built `CONCURRENTLY`, 216 ms, 1.2 MB) did not make it faster here, so it is optional and only worth it on a much larger table. | Do not proceed. |
| 4 | Final catch-up pass, then switch the app to the new column with an alias | live-safe | The catch-up is the same idempotent batch job (a rerun touched 0 rows when nothing had changed). The switch is a code deploy only. | Deploy the previous release; the legacy column was kept written, so reading it still works. |
| 5 | Keep writing the legacy column | live-safe | None: dual-write continues, now with the canonical value. | n/a |
| 6 | Rename in a short low-traffic window | **low-traffic window** | See "The rename" below. | Before the rename: a code deploy. After it: the reverse rename in one transaction plus the previous release. Restoring the backup is the last resort. |
| 7 | Drop `legacy_status` later | **low-traffic window** | ACCESS EXCLUSIVE for an instant: `lock_timeout` of about 2 s with retry. Take a backup first. Irreversible, so only after a quiet period of weeks. | Only from the backup. |

### Backfill design (step 2, Req 43)

- **Input:** the approved `db/status_mapping.yml` only. A draft file is refused.
- **Batches:** about 5,000 ids per batch, `WHERE id BETWEEN a AND b AND status_canonical IS NULL AND lower(btrim(status, E' \t\r\n')) = <mapped key>`, each batch its own short transaction (no long transactions), `SET statement_timeout` (5 s) and `lock_timeout` (2 s) for the session.
- **Idempotent and resumable:** only rows still NULL are touched, so a rerun fills only what is missing (it touched 0 rows on the second run); the job prints the last id of each batch and takes a start id to resume.
- **Throttle and pause:** after each batch it sleeps in proportion to the batch time and **pauses** when any agreed threshold trips: **replication lag over 5 seconds**, **any lock wait over 2 seconds**, or **request latency over 1.5 times baseline**. Lag comes from the follower's `pg_stat_replication` lag, lock waits from `pg_stat_activity` (`wait_event_type = 'Lock'`), latency from the host's request metrics.
- **Rehearsal:** 100 batches of 5,000 ids took a median of 60 ms (95th percentile 92 ms, longest 130 ms), 5.7 s in total for 446,246 rows (the 53,754 unmapped rows are left NULL). Short batches mean locks on rows only for milliseconds and nothing on the whole table.
- **What the rehearsal also showed, and why the throttle matters:** only 3,434 of the 446,246 updates were HOT (heap-only) updates, because the new column fills pages that are already full, so about every update wrote a new row version and new index entries. The table and indexes grew from 294 MB to 541 MB with 443,210 dead rows. In production that is extra WAL (which is what drives replication lag) and bloat that autovacuum must clean. Mitigations: small batches with the throttle above; schedule the job off-peak; let autovacuum keep up or run `VACUUM (ANALYZE) assessments` between big runs; watch lag and disk. Not measured here: WAL volume and autovacuum behaviour under real load.
- **Indexes:** none on the new column during the backfill (an index would be written on every update). Any index later is built `CONCURRENTLY`.

### The rename (step 6, Req 32)

1. Announce the window. Capture a backup **immediately before**: `heroku pg:backups:capture --app <app>`, then confirm it with `heroku pg:backups:info`.
2. `heroku maintenance:on --app <app>`. Rails caches column names, so dynos running the old code break the moment the columns change; maintenance mode covers that gap.
3. In one transaction: `SET LOCAL lock_timeout = '2s'; ALTER TABLE assessments RENAME COLUMN status TO legacy_status; ALTER TABLE assessments RENAME COLUMN status_canonical TO status;` Each statement took under 0.5 ms here, so the lock is held for well under a millisecond; the real risk is waiting for the lock, which `lock_timeout` bounds. If it times out, nothing changed: retry.
4. Deploy the code that uses plain `status` (the alias removed, dual-write still writing `legacy_status`) and restart all dynos.
5. `heroku maintenance:off --app <app>`; smoke-test the dashboard, an export and the assessor screen.
- **Rollback.** Before the rename: deploy the previous release (`heroku releases:rollback`). After it: the reverse rename in one transaction (rehearsed, under 0.5 ms per statement) and the previous release. **Restoring the backup is the last resort** (`heroku pg:backups:restore <backup> DATABASE_URL --app <app> --confirm <app>`), because it loses every write made after the backup.
- Rehearse the whole sequence on a copy first (`heroku pg:copy` to a staging app).

## Lock and responsiveness safeguards, in one place (Req 43)

| Safeguard | Where it applies |
|---|---|
| Short `lock_timeout` (about 2 s) with retry | Add column (1), rename (6), drop (7) |
| Id batches of about 5,000 and a throttle | Backfill and catch-up (2, 4) |
| Pause when replication lag over 5 s, any lock wait over 2 s, or request latency over 1.5 times baseline | Backfill and catch-up (2, 4) |
| No long transactions: one short transaction per batch | Backfill (2) |
| `statement_timeout` on the backfill session (5 s) | Backfill (2) |
| Any index on the new column built `CONCURRENTLY` (and none during the backfill) | Verification, if used (3) |
| Verification counts on a follower, or on a partial index | Verification (3) |
| Backup immediately before the rename; restore only as a last resort | Rename (6), drop (7) |
| Maintenance mode only for the rename window | Rename (6) |

## What this plan does not do

- It executes nothing: no migration, no backfill code in the repository (guard tests: `test/lib/status_guards_test.rb`).
- No database constraint on `status` (the author's decision: the rule belongs in Ruby, not the database). A check on the clean column after the switch is possible future work.
- The assessor-side front end and API changes outside this repository are only described.
- Numbers are local and relative: rehearsed on a throwaway copy of the development database (the copy was dropped afterwards). Production and staging must be measured before any date is promised.
