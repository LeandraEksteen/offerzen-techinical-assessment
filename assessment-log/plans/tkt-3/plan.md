# TKT-3 plan: async company-scoped CSV export

Status: plan, not yet approved. Source ticket: `assessment-log/tickets/TKT-3.md`. Spec: `assessment-log/spec/` (Req 4 to 11, 13 export flows, 36).

## Why this matters
Company admins keep asking for an export. Today's behaviour, as the brief describes it, lets anyone pull any company's data by passing an identifier and includes raw answers and personal identifiers. This ticket builds the safe version: an admin can export only their own company's assessments, with two filters and no personal data, without freezing the page or the web server for a company holding ten years of data.

## Architecture overview
An admin opens the exports page, sets an optional date range and status, and clicks export. The server validates, creates an `ExportRequest` row (state `in_progress`), enqueues `ExportJob` with that record, and redirects to the same page, where a history table shows the new row and a refresh message. The job builds the CSV in batches from a fixed list of columns, attaches it with Active Storage, and sets the row to `ready`. The history row then links to an authorised download. Rows older than 7 days read as `expired` and a recurring job purges their files. A small Stimulus controller in TypeScript gives submit feedback.

## What the repo changes about the spec's assumptions (read from `origin/main`)
1. **Active Storage has no tables.** The schema has none; the PR runs `active_storage:install` (3 tables).
2. **Active Storage's default blob links are bearer links.** A signed URL works without signing in, which would break "link returns 404 for another company". Plan: draw no Active Storage routes (`draw_routes = false`) and serve the file through our own authorised action.
3. **Jobs:** development has no adapter set, so Rails runs the in-process `:async` adapter (jobs run inside the web server and are lost on restart); `Procfile.dev` has no worker. Production uses `solid_queue` with its own database and needs a worker (`bin/jobs` or `SOLID_QUEUE_IN_PUMA`); to go in the README and `SOLUTION.md`.
4. **Cache:** test uses `:null_store`, so the 10-minute cache can only be tested by swapping in a memory store inside the test.
5. **"Whole UTC days"** (Req 5) is moot: `assessment_date` is a `date`, so the range is simply inclusive on dates.
6. **A job that dies mid-run** would leave a row `in_progress` forever and, with one in progress per admin, block that admin. Not in the spec; see Open questions.

## Requirements
Req 4, 5, 6, 7, 8, 9, 10, 11, 36 fully; Req 13 for the export flows (dashboard part is TKT-8).

## Design

| Piece | What it does |
|---|---|
| Migration: Active Storage | `bin/rails active_storage:install`, then migrate |
| Migration: `export_requests` | `company_id` (indexed), `admin_id`, `state` string (`in_progress`, `ready`, `failed`, `expired`), `date_from`, `date_to` (dates, nullable), `status_filter` (string, nullable), `row_count`, `finished_at`, timestamps; index on `(company_id, created_at)`; partial unique index on `admin_id` where `state = 'in_progress'` so two clicks cannot both start |
| `ExportRequest` model | `belongs_to :company, :admin`; `has_one_attached :file`; `enum :state`; scopes `recent` (20, newest first), `stale` (in progress for more than 30 minutes, treated as failed); `expired?` is true after 7 days from `created_at`, whatever the stored state; validation that no other export for the admin is in progress |
| `StatusOptions` service | Distinct statuses of one company: `lower(btrim(status))`, null/empty/blank grouped as one "(no status)" entry, cached 10 minutes per company; `valid?(value)` checks the cached list and re-reads once uncached before rejecting. Reused by the dashboard filter in TKT-4. |
| `AssessmentCsvExport` service | Fixed columns `assessment_id, assessment_date, created_at, status, score, employee_id`. Raises at load if any column is a declared PII attribute. Reads the company's rows in batches of 5,000 ordered by id (`id > last`), with the date and status filters in SQL. Score is taken in SQL: `jsonb_typeof(responses_json->'score') = 'number'`, so only a JSON number ever leaves the database and free text never reaches Ruby. Rows pass through `Pii::Scrubber.scrub_attributes` as a second guard. Status cells starting with `=`, `+`, `-` or `@` get a leading apostrophe. Writes to a tempfile, never to memory. |
| `ExportJob` | `perform(export_request)`; builds, attaches `assessments-export-<id>.csv` as `text/csv`, sets `ready` and `row_count`. On any error: set `failed`, log only the error class and the export id, no retry, no re-raise. |
| `ExpireExportsJob` | Deletes the files of exports older than 7 days and sets `expired`. Entry in `config/recurring.yml` (production); the `expired` display does not depend on it running. |
| `ExportsController` | `index` (form plus history of the signed-in admin's company only), `create` (strict params: `from`, `to`, `status`; invalid input renders 422 with a plain message and creates nothing), `show` (download: finds the export through `current_company.export_requests`, so another company's id is a 404; sends the file with `send_data`; non-ready exports are 404). A `company_id` parameter is never read. |
| Views | `exports/index`: form with date inputs and the status select ("All", "(no status)" when present, then the options), the history table (created, filters, state, rows, download link), and the message "Exports can take a few minutes. Refresh this page to check progress." while any export is in progress. Home page gains a link. |
| TypeScript | `export_form_controller.ts` (Stimulus): on submit, disable the button and show "Starting export…"; on a failed response, re-enable and let the server-rendered error show. Registered in the controller index. No other TypeScript. |
| `config/application.rb` | `config.active_storage.draw_routes = false` |

## Changes required (single repo)

| Area | Files | Complexity |
|---|---|---|
| Migrations and schema | 2 migrations, `db/schema.rb` | Low |
| Models and services | `export_request.rb`, `status_options.rb`, `assessment_csv_export.rb` | Medium |
| Jobs | `export_job.rb`, `expire_exports_job.rb`, `config/recurring.yml` | Medium |
| Web | `exports_controller.rb`, `config/routes.rb`, 2 views, home link | Medium |
| TypeScript | `export_form_controller.ts`, `controllers/index.ts` | Low |
| Tests | 18 unit and integration cases | High |
| Assessment log | Ticket, decisions, prompts, spec amendments | Low |

## Contract summary
None. Single-repo change; boundaries checked are in `contract.md`.

## PR strategy
One PR, base `main`, branch `feat/TKT-3/async-csv-export`. The yaml is in `pr-strategy.yaml`. This is the biggest ticket so far (about 25 files and 900 lines with tests, at the edge of the one-PR guideline); I'd keep it as one PR because the pieces (page, job, download, expiry) only make sense together.

## Test matrix

| ID | Req | Case | Type | Bucket | PR |
|---|---|---|---|---|---|
| UT-1 | 4 | Two companies: A's export holds only A's rows; a `company_id` parameter is ignored | positive | unit | 1 |
| UT-2 | 4 | Admin B gets 404 for A's download; signed-out users are redirected | negative | unit | 1 |
| UT-3 | 8 | Header is exactly the six columns; no email, free text or raw JSON in the file | positive | unit | 1 |
| UT-4 | 8 | Status cells starting `=`, `+`, `-`, `@` are neutralised | edge | unit | 1 |
| UT-5 | 8 | The exporter refuses a column list containing a declared PII attribute | positive | unit | 1 |
| UT-6 | 9 | Numeric score exported; string, null, missing, array, double-encoded and null root blank | positive | unit | 1 |
| UT-7 | 5, 6 | Filters: inclusive range, either end optional; status variants match; no-status matches nil, empty and blank; `n/a` separate | positive | unit | 1 |
| UT-8 | 5 | Invalid date, reversed range or unknown status gives 422 and creates nothing | negative | unit | 1 |
| UT-9 | 6 | Status options distinct per own company, grouped, lowercased, no-status once, cached 10 minutes, data untouched | positive | unit | 1 |
| UT-10 | 7 | Create gives an in-progress row and refresh message; job enqueued with the record only; after the job: ready with a link; history shows the 20 most recent of the own company | positive | unit | 1 |
| UT-11 | 7 | Job exports every row across several batches in stable order | positive | unit | 1 |
| UT-12 | 10 | Job error sets failed with the generic text, no retry, no data in page or log | negative | unit | 1 |
| UT-13 | 10 | Second create while one runs is refused; the index blocks a race | edge | unit | 1 |
| UT-14 | 10 | In progress for more than 30 minutes counts as failed so a new export can start | edge | unit | 1 |
| UT-15 | 10 | Older than 7 days shows expired and cannot be downloaded; purge job removes the file | positive | unit | 1 |
| UT-16 | 11 | File attached through Active Storage as plain `text/csv`; no Active Storage routes drawn | positive | unit | 1 |
| UT-17 | 13 | Successful and failing exports leave no emails, response content or raw scores in the captured log | positive | unit | 1 |
| UT-18 | 36 | Page wires the Stimulus controller; `yarn typecheck` passes | positive | unit | 1 |
| MC-1 | 7 | Real browser walk-through, download and cross-company 404 | positive | manual | 1 |
| MC-2 | 7 | Export the 200,000-row company; record time, size, responsiveness | positive | manual | 1 |

## Risks and mitigations
- **Unauthorised download via Active Storage links:** no routes drawn; download only through the company-scoped action; UT-2 and UT-16.
- **Personal data leaving the database:** fixed columns, numeric-only score read inside SQL, PII guard on the column list, scrubber on rows; UT-3, UT-5, UT-6.
- **Job dies without finishing:** stale in-progress treated as failed after 30 minutes (UT-14).
- **Large export memory:** batches of 5,000 and a tempfile, nothing held in memory; MC-2 measures it.
- **Slow batch queries:** `assessments` has no secondary index (by design until TKT-7), so each batch is a primary-key range scan filtered by company; one pass in total per export. MC-2 records the time.
- **Formula injection:** only text cells (status) are prefixed; numbers are left intact.
- **Invariant writers:** none; no stored invariant beyond the unique in-progress index.
- **Spec amendments needed:** reversed date range gives 422 (Req 5); stale in-progress after 30 minutes (Req 10); both go back into the spec with `--amend` once you agree.

## Open questions (need your decision)
1. **Download method:** serve through an authorised action with `send_data` and draw no Active Storage routes. Accept? (Alternative: signed redirect, which is a bearer link for its lifetime.)
2. **Stale exports:** an export in progress for more than 30 minutes counts as failed, so the admin can retry. Accept? (Needs a spec amendment on Req 10.)
3. **Reversed date range:** `from` after `to` returns 422 instead of an empty export. Accept? (Amendment on Req 5.)
4. **Refresh behaviour:** the form posts with Turbo, the server redirects straight to the history page (well inside 2 seconds), and TypeScript only disables the button, shows "Starting export…" and handles errors. No timer reload. Accept, or do you want an explicit timer?
5. **Status validity:** a submitted status is checked against the company's cached options, re-reading once uncached before returning 422. Accept?
6. **Expiry job:** one entry in `config/recurring.yml` (production only, since only production has a scheduler) plus the expired display that works without it. Accept?
7. **Size:** one PR of about 25 files. Accept, or split off the expiry piece?

## Out of scope
Polling, a global done-banner, emailing the CSV, any export taking a company identifier (Req 37, 38); score normalisation (TKT-8); the dashboard; S3 configuration.

## Critic pass
Not run as a separate agent: single repo, no contract items. The checks above stand in.

## Self-check
- Every active requirement in scope (4 to 11, 13 for exports, 36) lands in PR 1 and has at least one unit case; Req 13's dashboard flows are explicitly TKT-8's.
- The two behaviour decisions made here (reversed range, stale in-progress) are raised as open questions and will be written back to the spec after approval.

## Implementation notes (added after building)
- Built as planned. Two additions outside the planned files, added to the PR scope: `config/database.yml` gets `gssencmode: disable` (the full suite crossed 50 tests, so Rails started forking parallel workers and libpq segfaulted on macOS; this is harmless elsewhere), and the `csv` gem is declared in `Gemfile` (it leaves the default gems in Ruby 3.4).
- The spec was amended for the two decisions made in planning: reversed date range returns 422 (Req 5), an export in progress for more than 30 minutes counts as failed (Req 10).
- `filter_parameters` can be compiled into a regexp by Rails, so "is this name already filtered?" is answered by our registry, not by searching the array (found while hunting a flaky test in TKT-2's tests; the macro and the test were corrected).
- Results: see the 2026-11-07 comment in `tickets/TKT-3.md`.

