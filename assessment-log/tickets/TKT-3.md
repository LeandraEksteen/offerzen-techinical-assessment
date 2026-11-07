---
key: TKT-3
type: Task
title: Task 1: async company-scoped CSV export with history table and minimal TypeScript UI
status: In Review
parent: EPIC-1
updated: 2026-11-07T09:21:32Z
---

## Description
**Context:** Company admins need to export assessments for their own company. The company has ten years of data, so the export runs as a background job and the page shows a history table.

**Scope:** Export request and download pages; the job building the CSV in batches; history table of the 20 most recent exports of the admin's company; the two filters (assessment date range, status select built from the company's own distinct stored statuses, grouped without changing data, cached 10 minutes); Active Storage attachment; 7-day expiry job; generic failed message; one export in progress per admin; minimal TypeScript form (submit, in-progress message, refresh after about 2 seconds, errors); formula-injection guard.

**Not in scope:** Streaming, polling, a global done-banner, emailing the CSV, any legacy export that takes a company identifier (Req 37, 38). Score normalisation (TKT-8): until then the score column is emitted only when it is a JSON number.

**Depends on:** TKT-1, TKT-2

**Spec requirements:** Req 4, Req 5, Req 6, Req 7, Req 8, Req 9, Req 10, Req 11, Req 13, Req 36 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- Company always comes from the signed-in admin, never a parameter; cross-company download returns 404.
- SOLUTION.md must justify async and note that production needs S3-style storage because the local disk is ephemeral on a Heroku-like host.
- Req 13 here means the export flows; the dashboard part is checked in TKT-8.

## Acceptance criteria
- Req 4: A test with two companies shows admin A's export contains only company A rows; a request carrying a company_id parameter for company B still exports company A; a download link for company A's export returns 404 for admin B.
- Req 5: The export form has only a date range (on assessment_date, inclusive, whole UTC days, either end optional) and a status select; blank status means all; an invalid date or an unknown status returns 422 with a plain message and creates no export; there is no row cap.
- Req 6: For a company whose rows hold 'Complete', 'complete ' and 'COMPLETE' the select shows one option labelled 'complete' that filters all three; nil, empty string and blank-only share one option '(no status)' that filters all of them; 'n/a' is its own option; options come only from the admin's company; the list is cached for 10 minutes per company; no stored status is modified.
- Req 7: Clicking download creates a history row with status 'in progress' and the page refreshes within about 2 seconds to show it plus a message to refresh in a few minutes; a background job builds the file in batches; when done the row shows 'ready' with a download link; the history lists the 20 most recent exports of the admin's own company; no polling or global banner exists.
- Req 8: The CSV header is exactly assessment_id, assessment_date, created_at, status (raw stored value), score, employee_id; a test asserts no employee_email, free-text answer or raw responses_json content appears; any cell starting with =, +, - or @ is neutralised against formula injection.
- Req 9: Rows whose responses_json has numeric score export that number; rows with a string, null, missing key or non-object JSON export a blank score; no free text can reach the score column.
- Req 10: A job error sets the row to 'failed' with the generic text 'Export failed, please try again' and no data or technical detail in the UI or logs; there is no automatic retry; a second click while one is in progress shows 'an export is already in progress' and creates nothing; files older than 7 days are deleted and their row shows 'expired'.
- Req 11: Files are attached via Active Storage on local disk in dev and test; SOLUTION.md states that production needs S3-style storage because the local disk is ephemeral on a Heroku-like host; the file is not zipped.
- Req 13: After a scripted run of an export (including a failing one) and dashboard loads with filters, the captured log and error output contains no employee email, response content or raw score value (checked by a test that greps the captured log).
- Req 36: TypeScript is limited to the export form behaviour (submit, show 'in progress', refresh after about 2 seconds, show errors); yarn typecheck passes; no other TypeScript features exist.

## Definition of done
- PR links this ticket (`TKT-3` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
- 2026-11-07 implementation: Active Storage tables and `export_requests` (partial unique index: one in progress per admin); `ExportRequest`, `StatusOptions`, `ExportFilters`, `AssessmentCsvExport` (fixed six columns, batches of 5,000, numeric-only score read inside SQL, formula guard, PII column guard), `ExportJob`, `ExpireExportsJob` (recurring in production), `ExportsController` (create, index, authorised download; no Active Storage routes), exports page, small Stimulus controller in TypeScript. Spec amended for two decisions: reversed date range gives 422 (Req 5); an export in progress for more than 30 minutes counts as failed (Req 10). Checks: `bin/rails test` 88 runs, 387 assertions, 0 failures (stable over 8 consecutive runs); `bin/rubocop`, `bin/brakeman`, `bin/bundler-audit`, `yarn typecheck` clean. MC-1: real dev server, as the seeded admin of the big company: exports page loads, an export of everything returned immediately with the in-progress message, was ready after 4 seconds, downloaded as `text/csv` with the exact header; another company's admin got 404 for the link, a signed-out request was redirected, the Active Storage blob route returned 404; no email appeared in the new log lines. MC-2: 200,000 rows exported in 3.8 seconds (10.8 MB), nothing held in memory. Out-of-range scores (for example 150 and -5) are exported as stored numbers by design; the score reader in TKT-8 handles them. Findings: parallel test workers segfaulted inside libpq on macOS once the suite passed 50 tests, fixed with `gssencmode: disable` in `config/database.yml`; the `csv` gem is now declared because it leaves the default gems in Ruby 3.4.
