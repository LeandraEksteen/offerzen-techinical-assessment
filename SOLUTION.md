# SOLUTION: safely extending a legacy Rails Assessments module

This is the design write-up for the take-home. It explains what was built, why, what it costs, and what was deliberately left out. To run the app, see [README.md](README.md). The thinking behind it (every prompt, numbered decisions, the spec and one ticket per piece of work) is in [assessment-log/](assessment-log/README.md); decisions are cited here as `D-nnn` and indexed at the end.

**The scenario.** A ten-year-old Rails app used by companies to manage ergonomic and health assessments for employees. The brief gave three tasks: a company-scoped CSV export, a faster dashboard with a trustworthy score, and a safe plan to normalise status values. The data is health related, the `assessments` table is large, and admins of one company must never see another company's data. Those three facts drive nearly every choice below.

**What exists in the repo.** The repo started as a bare Rails 8.1 scaffold with no domain code, so a small scaffold came first (tables, admin sign-in, a deterministic 500,000-row messy seed). Everything after that is one ticket and one pull request each:

| Ticket | PR | What it delivers |
|---|---|---|
| TKT-1 | 7 | Scaffold: data model, admin sign-in, large messy seed data |
| TKT-2 | 8 | One PII scrubber for logs, error logs and exports |
| TKT-3 | 9 | Task 1: asynchronous company-scoped CSV export with a history table |
| TKT-4 | 10 | Task 2: deliberately slow baseline dashboard and the benchmark method |
| TKT-5 | 11 | Task 2: pagination |
| TKT-6 | 12 | Task 2: eager loading |
| TKT-7 | 13 | Task 2: one composite index, built concurrently |
| TKT-8 | 14 | Task 2: score reader shared by dashboard and export, and a score report |
| TKT-9 | 15 | Task 3: assessor status screen, free text (the "before") |
| TKT-10 | 16 | Task 3: status rule, default, cut-over date and dropdown (the "after") |
| TKT-11 | 17 | Task 3: status report and the backfill, release and rollback plan |
| TKT-12 | 18 | Docs: README, this document |

Performance work is split into four separate changes on purpose (pagination, eager loading, index, score reader): each is revertible alone and each has its own before and after numbers, so no claim here rests on "it feels faster".

## Task 1: company-scoped CSV export

### What it does
An admin picks an optional assessment-date range and an optional status, clicks "Export CSV", and a background job builds the file. The page shows a history of the admin's company's 20 most recent exports (in progress, ready, failed, expired) with a download link when ready. Exactly two filters exist, as the brief asks. The date filter uses `assessment_date`, not `created_at`, because an assessment can be scheduled but not yet completed (D-009); both ends are inclusive and a start after the end is rejected with a 422. The status list is the distinct statuses the company actually has, trimmed and case-insensitive, with NULL, empty and blank grouped as "(no status)" (D-012).

### Why asynchronous
The brief allows streaming or asynchronous and asks for the choice to be justified (D-007, D-021). I chose asynchronous:

- **No ceiling on size.** There is no row cap and any date range is allowed; the company has ten years of data. A synchronous or streamed response holds a web worker for as long as the file takes, and a long request is exactly what freezes a busy app.
- **The measured case is small but not the limit.** The largest company in the seed (200,000 rows) exports in a median of 2,552 ms locally (3,767 ms before the score reader sped it up). That is fine as a background job and would still be a long time to hold a request; production has a slower disk, an upload to object storage, and tables that keep growing.
- **A history table is more useful than a download button.** It shows what is running, survives a refresh, gives a retry path after a failure, and makes the download an authorised request rather than a one-off stream.
- **Cost accepted:** V1 has no polling and no global "export ready" banner; the page tells the user to refresh in a few minutes, and a small TypeScript controller gives immediate feedback on submit. Polling and a banner are in Future work.

Operationally: one export may be in progress per admin (a validation and a partial unique index), a duplicate click is refused, an export still "in progress" after 30 minutes counts as failed so the admin can retry, and finished exports and their files are kept for 7 days. The file is built in batches of 5,000 rows into a tempfile and attached with Active Storage.

### Tenant isolation
The company comes **only** from the signed-in admin's session (`current_company`), never from a parameter. The export page, the history and the download are all looked up through that company, so another company's export is a 404 (it does not even confirm the id exists). Two-company tests cover this for the export, the dashboard and the status screen. Sign-in is a plain email and password form against a table (`has_secure_password`), rate limited to 10 attempts in 3 minutes (D-010, D-019).

### The legacy export, control by control (Req 38)
The brief describes the legacy behaviour. No insecure version was built (D-011); this is how each point is addressed:

| Legacy behaviour in the brief | Control in this app |
|---|---|
| The export can pull assessments for any company when given a company identifier | No endpoint accepts a company identifier. The company is the session's company; a client-supplied id is ignored; a cross-company download is a 404 |
| It includes raw answer data | Only six fixed columns can leave: `assessment_id`, `assessment_date`, `created_at`, `status`, `score`, `employee_id`. `responses_json` is never exported; the score is read inside the database from four candidate keys, so free-text answers never reach Ruby |
| It includes personal identifiers | No email or name column exists in the allow-list; the exporter refuses to run if any column is a declared PII attribute; rows also pass the PII scrubber as a second guard; the `employee_id` is an internal number |
| Logs include full request parameters | One PII declaration per model feeds Rails' parameter filter, so declared values show as `[FILTERED]`; a log formatter scrubs every line as a backstop |
| Logs occasionally include raw assessment data | Job arguments are ids or records only and are never logged; the seeder silences bulk SQL; the formatter scrubs emails and declared values in hash, JSON, key-colon and SQL shapes; tests assert the logs of the export and the dashboard contain no emails or scores |

Other controls: status cells are guarded against spreadsheet formulas (a cell starting with `=`, `+`, `-`, `@`, tab or CR gets a leading apostrophe); the download is served only through an authorised controller action, and Active Storage's default blob routes (which work without signing in) are not drawn at all.

### Storage (Req 11)
Files are attached with Active Storage on local disk in development and test. **Production on a Heroku-like host needs S3-style object storage:** the dyno filesystem is ephemeral and not shared between web and worker dynos, so a file written by a job on one dyno would not be there when another dyno serves the download. The repo's production setting still points at the local service because no cloud account exists for this exercise; the change is a storage service entry in `config/storage.yml` plus `config.active_storage.service`, with the bucket private and downloads still going through the authorised controller action. Not done.

### The job worker
Development runs jobs inside the Rails server process (Rails' default in-process adapter). Production uses Solid Queue: run `bin/jobs` as a worker process, or set `SOLID_QUEUE_IN_PUMA` to run it inside Puma (as `config/deploy.yml` does). The production queue database is configured in `config/database.yml` but was not exercised here.

### The PII scrubber (D-008, D-020)
One declaration per model (`pii_attributes`) registers names once and drives four things: the scrubber, Rails' request parameter filter, `inspect` redaction, and the export guard. Declared: assessment email and `responses_json`, employee name and email, admin email and password digest. A log formatter then scrubs every line, including error logs, and fails closed; production builds its own logger, so the formatter is passed to it explicitly. The primary protection is not logging data in the first place. **Known limits:** positional values in bulk `INSERT` SQL cannot be matched by attribute name (only emails are caught); `as_json`, `pluck` and rendered HTML are not scrubbed; the global parameter filter also hides any parameter called `name`; the development error page can show values.

### TypeScript
TypeScript is limited to one Stimulus controller on the export form: it disables the button and shows "Starting export…" while the form submits and re-enables it on an error. `yarn typecheck` passes. Nothing else is TypeScript (Req 36).

## Task 2: the dashboard

### How it was measured (and what these numbers are not)
Method and raw results are in [assessment-log/benchmarks/task-2-dashboard.md](assessment-log/benchmarks/task-2-dashboard.md). **All numbers are local, not production:** Apple M1 Pro, Ruby 3.3.3, Rails 8.1, PostgreSQL 16.9 with default settings and a warm cache, development mode, on the seeded database (500,000 assessments, 20 companies; the largest company has 200,000 and the one used as a "normal user" has 15,790). Each timing is the median of 5 runs after a warm-up (one run, with a 10-minute limit, for the largest unpaginated page). Bullet and rack-mini-profiler found the problems, then were switched off while timing (the profiler alone made a 421 ms page take 1,292 ms). Database time is PostgreSQL's own `EXPLAIN (ANALYZE, BUFFERS)`, load tests use `ab` (ApacheBench; `hey` and `k6` were not installed), and write latency during an index build used `pgbench`. The seed was made realistic first: with 40 employees per company the query cache hid the N+1, so it now has about one employee per ten assessments (D-022).

### The baseline
The dashboard was first built as a deliberately legacy-style baseline (no pagination, one employee query per row, score shown as stored), because "before" numbers need something real to measure.

| Scenario | Rows | SQL queries | Median time | Page size |
|---|---|---|---|---|
| Normal user (Company 02, dates in 2024) | 1,516 | 1,414 | 421 ms | 284 KB |
| Company 02, all rows | 15,790 | 14,787 | 3,921 ms | 2,936 KB |
| Company 01 (largest), all rows | 200,000 | 199,064 | 58,019 ms (one run) | 37,287 KB, 2.09 GB peak memory |

Two findings shaped the plan. The number of queries is almost exactly the number of rows (the N+1). And the main database query takes only 44 to 153 ms in every scenario, so **most of the time is Ruby** (an object per row, a query per row, rendering a huge table), not the database. That predicted the order: pagination and eager loading first, the index last, and a much smaller gain from the index than people assume (D-022).

### The four changes, one at a time

| Change | Why this one | Before | After | Query count |
|---|---|---|---|---|
| **Pagination** (TKT-5, D-023): 50 rows per page, Previous and Next, no total count | The page's cost scales with rows; capping rows is the only fix that works for every company size | Largest company 58,019 ms; normal user 421 ms | 61 ms and 66 ms (950 and 6.4 times faster); page 37,287 KB to 12 KB | 199,064 to 53; 1,414 to 53 |
| **Eager loading** (TKT-6, D-024): the page's employees in one query selecting only id and email | Removes the per-row employee query; a dedicated association because a `select` on the relation does not apply to preloaded records, and a join would widen the sorted query | Normal user 66 ms; largest company 61 ms | 49 ms and 44 ms (about 26 to 30% faster) | 53 to 4 (constant for any page size) |
| **Composite index** on `(company_id, assessment_date)` (TKT-7, D-025), built `CONCURRENTLY` | The main query still scanned and sorted the whole company to find 50 rows | Main query 43 ms; page 46 to 51 ms | Main query 0.15 to 0.21 ms; page 7 to 8 ms (6.4 to 6.7 times faster) | 4 to 4 |
| **Score reader** (TKT-8, D-026) | Fixes what the Score column shows (next section) and must not slow anything | Page 6 to 7 ms; 200,000-row export 3,767 ms (median of 3) | Page 6 to 7 ms; export 2,552 ms median | 4 to 4 |

Cumulatively the normal user's page went from 421 ms and 1,414 queries to 7 ms and 4 queries, and the largest company's from 58,019 ms and 199,064 queries to 6 ms and 4. `ab` load test on the normal-user page: 2.44 requests per second at concurrency 1 (20 requests, baseline) to 157.13 on a warm server at the end (40 requests; not the same request count, so indicative); 2.98 to 172.57 at concurrency 3. Each step's own table and its `ab` numbers are in the benchmarks file; page 1 was proven unchanged after every step by comparing a snapshot of its first 50 rows (no emails), and only the score column changed, in the expected rows, after the score reader (19 of 50 and 16 of 50 in the two views).

Why a **concurrent** index build: a plain `CREATE INDEX` blocks inserts and updates for as long as it runs. With two clients inserting continuously, a plain build froze writers for up to 210 ms on 500,000 rows (minutes on a table a hundred times larger); the concurrent build took 0.34 s and the maximum insert latency stayed at 10 ms with none over 50 ms. PostgreSQL does not allow it inside a transaction, so the migration disables the DDL transaction, and because an interrupted concurrent build leaves an INVALID index that Rails' `if_not_exists` would silently keep, the migration first drops an invalid leftover of the same name. A test reads `pg_index` for valid and ready. Rollback is a concurrent drop. Three index shapes were tried before choosing the two-column one the spec names; a three-column one was about 3 times faster again at the database but 3.3 times larger (19 MB against 5.7 MB) and dearer to write, so it is the documented option rather than the choice. Write overhead was not measurable above noise at this size (0.096 ms against 0.088 ms per insert); it grows with the table.

### What is still slow
- **Deep pages.** Page 3,000 (offset 149,950) still scans and sorts the company: 164 to 176 ms with or without the index (95 ms in the last run, noise, no change was made). Offset pagination cannot be fixed by an index; keyset pagination (a cursor of date and id) would fix it but cannot say "page 3".
- **The status list in the filter form** runs a `SELECT DISTINCT` over the company's rows: about 58 ms for the largest company whenever its 10-minute cache is empty. No index the spec allows helps it.
- **The export's date filter** reads batches in id order and filters as it goes (27 ms per 5,000 rows for a one-year range); only the three-column index would turn that into an index-only scan (4.3 ms).

### Log hygiene on the dashboard (Req 14)
Request logs show the filter parameter names but not employee emails or score values: emails come through the shared PII scrubber and parameter filter, the dashboard no longer loads `responses_json` at all, and if reading one row's score fails only the error class and the assessment id are logged. Tests assert this for a request with filters.

## The score assumptions (Req 18)

The score reader's contract is also the header comment of `app/services/score_reader.rb`; the report is `bin/rails scores:report`. The full text follows.

### We do not know the real data

The brief says the score shown to admins is "sometimes blank or obviously off" and says nothing about where the score is stored, what scale it uses, or how ten years of changes to the system left their mark on it. We are effectively blind. The reader is an educated guess that covers legacy problems seen before in systems like this one, kept small and written so that its rules can be removed once the real data is known.

### What the reader assumes

1. **Where the score lives:** the top-level keys `score`, `assessment_score`, `total_score` and `overall_score`, in that order. The first one that holds a valid value wins. Values are never combined. Nested keys, other names, and scores computed from individual answers are not looked at.
2. **What counts as a number:** a JSON number, or a string that is, after trimming, digits with an optional single decimal part (`.` or `,`) and an optional percent sign (a space before it is allowed). Text such as `"N/A"`, an empty string, `"85 out of 100"` and `"1.234,5"` are not numbers. A comma followed by exactly three digits (`"1,234"`) could be a thousands separator, so it is treated as ambiguous and invalid.
3. **Range:** 0 to 100. Anything outside is invalid. A value strictly between 0 and 1 (`0.85`) could mean 0.85 or 85, so it is **not** scaled: it is invalid and counted separately.
4. **Rounding:** half up, to a whole number.
5. **Result:** a whole number 0 to 100, or nothing. Nothing is shown as "Score not available" on the dashboard and left blank in the CSV. The status of the assessment never matters.

### Legacy problems it is meant to cover

Scores stored as text (`"85"`), with a percent sign (`"85%"`), with a decimal comma (`"84,5"`), with float noise (`84.99999`), under an older key name, next to a second score, missing, null, as `"N/A"` or an empty string, outside 0 to 100, as a proportion, in a root that is not an object (a JSON string that was encoded twice, an array, null).

### What it deliberately does not do

- It never rewrites stored data. What an admin sees can therefore differ from what is stored: `"85%"` is stored and `85` is shown. This is intended and a Score that cannot be trusted is shown as "Score not available" rather than guessed.
- Scales such as 1 to 5 or 0 to 10 cannot be told apart from low percentages and are read as percentages. This is a known limitation.
- It does not gate the score on the assessment's status (the statuses are still messy; see the status plan).

### How it is built to be pruned

Each rule (key order, scalar only, string to number, percent sign, decimal comma, range, proportion, rounding) is a separate unit with its own tests, and a reader can be built without any of them. `bin/rails scores:report` runs the reader over every row and prints how many rows fall into each case, how many needed each rule, and a few scrubbed examples per case. Once real data has been run through it, delete the rules whose counts are zero.

### How it keeps personal data out

The four candidate values are read in SQL, so the free-text answers stored beside the score never reach Ruby (the export already worked this way). The dashboard no longer loads the large `responses_json` column at all. Neither the dashboard nor the report logs a score value; if reading one row fails, only the error class and the assessment id are logged. The report prints a raw score token only when it is short and number-like (and scrubbed), otherwise it prints `[text, N characters]`.

### Ideal validation

Take a masked copy of production data, run `bin/rails scores:report` on it, and look at the examples for each case. That is the only way to know whether these assumptions fit. On the synthetic seed (500,000 rows, deliberately messy) 81.0% of rows show a score and 19.0% show "Score not available"; the real proportions on real data are unknown.

## Task 3: status values

The brief asks for two things: an implementation so new and updated records use only the five allowed values (`pending`, `in_progress`, `completed`, `needs_follow_up`, `archived`), and a plan, not an execution, to bring historical records into line. Nothing in this repository changes a historical row.

### The write side, implemented (D-018, D-027, D-028)
- **The rule.** `Assessment` accepts only the five values, checked **only when a status is being set** (a new record or a changed status). So updating another field of a legacy row that holds `Complete ` still works; the dirty value is only refused if someone tries to set it. There is **no alias mapping on write** (a value like `done` is rejected, not translated) and **no database constraint**: the database is not responsible for this rule. A new assessment with no status (nil) is stored as `pending`; an empty string is not "no status" and fails.
- **The cut-over date.** In real life assessors would be told about the change in advance, with a date. `STATUS_CUTOVER_DATE` (an ISO date, inclusive) is read once at boot: **before** it, a would-be rejection saves anyway and logs one line with a running per-process count and no value (`status validation: would reject after cut-over (count=N)`), so the team can see how many writers still send old values; **on and after** it, the save fails with a clear message. Unset means enforce now (the end state is the default, the date only delays it); a malformed value stops the app at boot so the rule cannot silently never apply. Tests cover the day before, the day itself and after.
- **The assessor screen, before and after (Req 41).** A small screen edits one assessment's status for signed-in admins of its company (existing sign-in, no new role; another company's id is a 404). TKT-9 built the **free-text** version, which stores whatever is typed, including blank: the legacy behaviour and the "before". TKT-10 replaced the field with a **dropdown** of the five values that cannot be saved empty. Both versions are in git history (PRs 15 and 16). The screen refuses anything but the five values whatever the date, because the dropdown is live from day one; the date only governs other writers. A legacy value is shown as a note with a required "Choose a status" prompt, so pressing Save cannot silently turn an old value into `pending`.
- **Accepted bypasses.** The seeder (`insert_all`), `update_all`, `update_columns` and the console skip the validation. They are the legacy and migration paths (the backfill would use them), not user input. The count is per process and resets on restart: an indication, not an audit.

### The plan for historical records
What follows is the plan, kept as written. It is guarded by tests so that it stays a plan: raw SQL naming the status column exists in one place only (`StatusOptions::NORMALISED_SQL`), and no application code path updates historical statuses. The read-only report that supports it is `bin/rails statuses:report`; the mapping is the draft `db/status_mapping.yml`.

### The problem and the two constraints

The `assessments` table holds ten years of free-text statuses: `Complete `, `COMPLETE`, `comp`, `done`, `n/a`, empty, blank, NULL. The brief asks for a plan to bring the historical rows into line with the five canonical statuses (`pending`, `in_progress`, `completed`, `needs_follow_up`, `archived`), under two constraints: **keep the app responsive throughout** and **avoid changes that would lock or stall the large table**. Every step below is judged against those two.

### Order of events, and why

1. **Stop the bad data first (done, TKT-10).** Ruby rejects any non-canonical status on create and when a status changes, from a configured cut-over date (`STATUS_CUTOVER_DATE`); before that date it only logs a count of would-be rejections. The assessor screen is a five-option dropdown. There is no alias mapping on write and no database constraint: the database is not responsible for this rule.
2. **Change request goes out before the date** (outline below).
3. **The cut-over date passes.** From then no new dirty value arrives, so the set of historical values stops growing.
4. **Dual-write goes live** (step 1 below) before any backfill, so rows written meanwhile are already covered.
5. **Mapping approved** by assessors (sheet and mapping file below).
6. **Backfill, verify, switch, rename, later drop** (the seven steps).

Cleaning old rows before stopping new dirty ones would be a treadmill; that is why the order is fixed.

### The sheet and the versioned mapping file (Req 31)

- **The sheet.** `bin/rails statuses:report` prints one row per distinct status value as stored with a row count and the latest `updated_at`. That output is what goes into a shared sheet: **only distinct values with counts and a date, never rows or ids**. The status column is free text, so a value could be anything; the report scrubs emails and describes anything that looks like free text (over 40 characters or over 4 words) only as `[text, N characters]` with a REVIEW flag, and a human scans the output before it is shared. On the 500k seed it prints 14 rows in 4.7 seconds (`assessment-log/benchmarks/status-report-500k-seed.txt`).
- **Assessors confirm the doubtful values** (`n/a`, empty, blank, anything unfamiliar). Where in doubt we pull the assessors in; nothing is guessed.
- **The versioned mapping file.** The approved result is committed as `db/status_mapping.yml`: `version`, `approved`, `approved_by`, `approved_on`, and `mapping` from the normalised stored value (trimmed, lower-cased, the same normalisation `StatusOptions` uses; `__none__` for NULL, empty and blank-only) to one of the five. It is the only input the backfill uses, and the backfill refuses a file that is not approved. The file in the repo is a **draft**: the author's starting-guess aliases (`complete`, `comp`, `done`, `finished` to `completed`, and so on), with `approved: false`. NULL, empty, blank-only and `n/a` are deliberately left unmapped.
- **A value without an approved mapping stays NULL in the new column and blocks the switch.** That includes NULL, empty and blank-only rows: they need an approved target too (probably `pending`, but that is the assessors' decision, not an assumption of this plan).
- `statuses:report` also shows, once a mapping file exists, rows per mapped status and the number of unmapped values and rows. On the draft against the 500k seed: 446,246 rows would map, 53,754 rows in 4 distinct values would not.

### The change request (outline)

What goes to assessors and to anyone whose system writes statuses, before the cut-over date:

- **What changes:** the status field becomes a dropdown of five values (Pending, In progress, Completed, Needs follow up, Archived). Free text and the old spellings are no longer accepted.
- **When:** the cut-over date. Until then the app accepts the old values but counts them, so the date can be moved if too many writers still send them.
- **Who must act:** assessors (pick from the list); owners of any import, integration or script that writes statuses (send one of the five exact values; `Complete ` or `done` will be rejected from the date).
- **What happens to old records:** nothing at first. They keep their old text and stay editable; a later, separate step (this plan) maps them to the five values.
- **Who to contact:** the product owner and the engineering owner for the assessments module (names go in the real document).

### The new column, dual-write and a single owner of the name (Req 42)

- **Approach (plan only):** add a new nullable column (placeholder name `status_canonical`), fill it from the approved mapping, switch the app to it with an alias, then rename the old column to `legacy_status` and the new one to `status`. The rename is done later, in a quiet window, to avoid permanent technical debt and because other readers of the table exist.
- **Dual-write from the first deploy:** the model writes both columns. The new column gets the canonical value (after the cut-over date that is the status itself; before it, the mapped value or NULL). The legacy column keeps receiving the status.
- **Rows written during the backfill** are covered because dual-write is live before the backfill starts, and by a **final catch-up pass** before the switch (rows where the new column is still NULL and a mapping exists, plus any row whose `updated_at` is after the backfill started).
- **One owner of the name.** Raw SQL that names the status column lives in one place, `StatusOptions::NORMALISED_SQL` (used by the dashboard filter, the export filter and the status list); a guard test fails if a second place appears. Everything else reads `status` through ActiveRecord attributes. At the switch, `alias_attribute :status, :status_canonical` plus changing that one constant is the whole code change. (Rails resolves attribute aliases in `select` and `pluck`; to be proven by a test in the switch PR.)
- **Other writers** that bypass the model (console, scripts, another app, the seeder in development) can write only the old column. The catch-up pass and the verification counts exist to catch them.

### The seven steps (Req 34)

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

#### Backfill design (step 2, Req 43)

- **Input:** the approved `db/status_mapping.yml` only. A draft file is refused.
- **Batches:** about 5,000 ids per batch, `WHERE id BETWEEN a AND b AND status_canonical IS NULL AND lower(btrim(status, E' \t\r\n')) = <mapped key>`, each batch its own short transaction (no long transactions), `SET statement_timeout` (5 s) and `lock_timeout` (2 s) for the session.
- **Idempotent and resumable:** only rows still NULL are touched, so a rerun fills only what is missing (it touched 0 rows on the second run); the job prints the last id of each batch and takes a start id to resume.
- **Throttle and pause:** after each batch it sleeps in proportion to the batch time and **pauses** when any agreed threshold trips: **replication lag over 5 seconds**, **any lock wait over 2 seconds**, or **request latency over 1.5 times baseline**. Lag comes from the follower's `pg_stat_replication` lag, lock waits from `pg_stat_activity` (`wait_event_type = 'Lock'`), latency from the host's request metrics.
- **Rehearsal:** 100 batches of 5,000 ids took a median of 60 ms (95th percentile 92 ms, longest 130 ms), 5.7 s in total for 446,246 rows (the 53,754 unmapped rows are left NULL). Short batches mean locks on rows only for milliseconds and nothing on the whole table.
- **What the rehearsal also showed, and why the throttle matters:** only 3,434 of the 446,246 updates were HOT (heap-only) updates, because the new column fills pages that are already full, so about every update wrote a new row version and new index entries. The table and indexes grew from 294 MB to 541 MB with 443,210 dead rows. In production that is extra WAL (which is what drives replication lag) and bloat that autovacuum must clean. Mitigations: small batches with the throttle above; schedule the job off-peak; let autovacuum keep up or run `VACUUM (ANALYZE) assessments` between big runs; watch lag and disk. Not measured here: WAL volume and autovacuum behaviour under real load.
- **Indexes:** none on the new column during the backfill (an index would be written on every update). Any index later is built `CONCURRENTLY`.

#### The rename (step 6, Req 32)

1. Announce the window. Capture a backup **immediately before**: `heroku pg:backups:capture --app <app>`, then confirm it with `heroku pg:backups:info`.
2. `heroku maintenance:on --app <app>`. Rails caches column names, so dynos running the old code break the moment the columns change; maintenance mode covers that gap.
3. In one transaction: `SET LOCAL lock_timeout = '2s'; ALTER TABLE assessments RENAME COLUMN status TO legacy_status; ALTER TABLE assessments RENAME COLUMN status_canonical TO status;` Each statement took under 0.5 ms here, so the lock is held for well under a millisecond; the real risk is waiting for the lock, which `lock_timeout` bounds. If it times out, nothing changed: retry.
4. Deploy the code that uses plain `status` (the alias removed, dual-write still writing `legacy_status`) and restart all dynos.
5. `heroku maintenance:off --app <app>`; smoke-test the dashboard, an export and the assessor screen.
- **Rollback.** Before the rename: deploy the previous release (`heroku releases:rollback`). After it: the reverse rename in one transaction (rehearsed, under 0.5 ms per statement) and the previous release. **Restoring the backup is the last resort** (`heroku pg:backups:restore <backup> DATABASE_URL --app <app> --confirm <app>`), because it loses every write made after the backup.
- Rehearse the whole sequence on a copy first (`heroku pg:copy` to a staging app).

### Lock and responsiveness safeguards, in one place (Req 43)

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

### What this plan does not do

- It executes nothing: no migration, no backfill code in the repository (guard tests: `test/lib/status_guards_test.rb`).
- No database constraint on `status` (the author's decision: the rule belongs in Ruby, not the database). A check on the clean column after the switch is possible future work.
- The assessor-side front end and API changes outside this repository are only described.
- Numbers are local and relative: rehearsed on a throwaway copy of the development database (the copy was dropped afterwards). Production and staging must be measured before any date is promised.

## Security and privacy at a glance

| Risk (health data, many tenants) | Control |
|---|---|
| One company reading another's data | The company comes only from the session; every export, download, dashboard row and status edit is looked up through it; cross-company access is a 404 |
| Personal data in the export | Fixed six-column allow-list; no email or name; free text never reaches Ruby; the exporter refuses declared PII columns |
| Personal data in logs | One declaration drives the parameter filter, `inspect` and the log formatter; job arguments are ids only; tests assert clean logs |
| Spreadsheet formula injection | Cells starting with `=`, `+`, `-`, `@`, tab or CR are prefixed with an apostrophe |
| Unauthenticated file download | Active Storage's public blob routes are not drawn; downloads go through an authorised action |
| Sign-in abuse | Rate limit of 10 attempts in 3 minutes; passwords are bcrypt digests |
| Sharing data to build the status mapping | Only distinct values with a count and a date, never rows or ids; the report describes free-looking text by length only; a person scans it first |
| A misleading score | Never guessed: an unreadable score shows "Score not available"; stored data is never rewritten |

## Testing, CI and tooling
- **Tests:** a Minitest suite (over 200 tests) covering the models, services, controllers, jobs, log hygiene, the seeder, the migration, the report and the guards. `bin/rails db:test:prepare test`. Automated tests were optional in the brief; they exist because several of the promises (tenant isolation, nothing sensitive in logs, the date switch) are the kind that regress silently.
- **CI checks** (GitHub Actions on every PR and push to `main`): `bin/rubocop` (rubocop-rails-omakase), `bin/brakeman --no-pager`, `bin/bundler-audit`, the test suite and the system-test job. `yarn typecheck` is not in the CI workflow; it was run locally for every change.
- **Guard tests** protect decisions: the backfill stays a plan, raw status SQL stays in one place, and the docs themselves (`test/docs`) fail if a link breaks, a named rake task disappears, a required section goes missing or the seeded password appears in a document.
- **Diagnosis tools:** Bullet and rack-mini-profiler (development only), `EXPLAIN (ANALYZE, BUFFERS)`, `ab`, `pgbench`.

## Trade-offs and known limitations
- **Numbers are local.** Staging and production would be measured with APM before and after each change; none of that data exists for this exercise.
- **Offset pagination** stays slow for deep pages (164 to 176 ms at page 3,000); keyset pagination would fix it at the cost of "page 3".
- **The score rules are assumptions** about data nobody has seen. Displayed scores can differ from stored data by design; 1 to 5 or 0 to 10 scales are read as percentages.
- **The status list** in the filter form costs about 58 ms on a cache miss and is cached for 10 minutes per process.
- **The would-be-rejection count** is per process; with several web processes the log lines add up.
- **Request logs** print the `status` parameter (it is not a declared PII attribute) and the development SQL log prints saved values; only declared attributes and emails are scrubbed.
- **Production storage and the job worker** are described, not configured (no cloud account).
- **The backfill is a plan.** Its numbers come from a rehearsal on a throwaway copy of the development database and must be re-measured on staging before any date is promised.

## Future work
None of the following is implemented.
- **Polling and a global "export ready" banner** (V1 asks the user to refresh; D-007).
- **Status-based score gating or alerts** once statuses are clean: for example an alert or error log for a missing score on a completed assessment (D-015).
- **Staging and production measurement** of every performance change with APM, alongside the local numbers.
- **A masked production copy** to run `scores:report` and `statuses:report` against, then prune the score rules the real data never needs.
- **Executing the backfill** on staging, then production, following the plan, after the assessors approve `db/status_mapping.yml`.
- **Keyset pagination** for deep pages and, if the export's date filter becomes a hot path, the three-column index.
- **S3-style storage** and a production job worker for exports.
- **Emailing the CSV** (a nice-to-have; the stored-file route was chosen first).

## Appendix: index of decisions
The full text, with context and rationale, is in [assessment-log/DECISIONS.md](assessment-log/DECISIONS.md).
- D-001: Keep the log in `assessment-log/` inside the repo
- D-002: Prompts logged verbatim, with a summary at the top at the end
- D-003: Tickets are markdown files in `assessment-log/tickets/`
- D-004: Git workflow
- D-005: No commits, pushes or PRs without explicit permission
- D-006: The 4-hour timebox in the brief is ignored
- D-007: Task 1 export is asynchronous (background job + history table)
- D-008: A PII scrubbing service covers exports and logs
- D-009: Export date filter uses `assessment_date`, not `created_at`
- D-010: Admin login is a plain table-backed form
- D-011: No insecure legacy export is built
- D-012: Task 1 status dropdown lists the distinct stored status values
- D-013: Score contract for `responses_json`
- D-014: Score normalisation is read-time only
- D-015: Status does not gate the score display
- D-016: No "scores may differ" footnote on the dashboard
- D-017: Performance work is benchmarked and shipped one change at a time
- D-018: Task 3 approach
- D-019: Scaffold choices (TKT-1)
- D-020: PII scrubbing design (TKT-2)
- D-021: How the export works (TKT-3)
- D-022: The Task 2 baseline and how it is measured (TKT-4)
- D-023: Dashboard pagination (TKT-5)
- D-024: Eager loading with a column-limited association (TKT-6)
- D-025: One composite index, built concurrently (TKT-7)
- D-026: The score reader is read-time, SQL-fed and shared (TKT-8)
- D-027: The free-text status screen is a deliberate baseline (TKT-9)
- D-028: Status rule, cut-over date and dropdown (TKT-10)
- D-029: The historical backfill is a plan, not code (TKT-11)
