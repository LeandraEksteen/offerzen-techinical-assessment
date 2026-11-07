# EPIC-1 — Test plan: Safely extend the legacy Assessments module (Task 1: company-scoped CSV export)

Status: approved
Source: spec.md (approved 2026-11-07), plus the TKT-3 unit-test matrix in plans/tkt-3/pr-strategy.yaml
Environment: (run 2026-11-07) staging = local dev server (`bin/rails server -b 127.0.0.1`, dev database seeded with 500,000 assessments, jobs run inside the server); repo `offerzen-techinical-assessment`, branch `feat/TKT-3/async-csv-export` (PR 9, CI green), commit under test 1b9cf0d
Scope: Task 1 only: the company-scoped CSV export as an admin sees it (page, form, history, download, file contents, failure and expiry handling, logs). Not checked: the dashboard, the score reader, status normalisation, sign-in itself, and typing an invalid date or unknown status (the form's date picker and fixed list prevent it; unit tests only).
Summary: 18 cases, about 69 minutes for a full run, 9 high priority
Estimate basis: 69 = 3 min per case plus 15 for setup
Google Doc: none (no document connector in this session)
Google Sheet: none (no document connector in this session)
Copies: none
Test data: Run in a browser on `http://127.0.0.1:3055`. Sign in with the seeded admins using the seeded development password (set in the seed task; never written here). Admin 1 = Company 01 (200,000 assessments). Admin 2 = Company 02 (15,790). Admin 3 = Company 03. Admin 4 = Company 04. Admin 5 = Company 05. The small "Test Company X" with its own admin and four assessments, the extra history rows and the aged exports are created by engineering before the run (see each case). Known counts for Company 02 (as of the seed used in the 2026-11-07 run; TKT-4 changed the seeder to create about one employee per ten assessments, so the dev database was re-seeded and these counts, which depend on the random seed, must be re-derived before the cases are run again): 15,790 rows; status "complete" (all spellings) 2,850; no status 1,304; "n/a" 335; assessment dates 2024-01-01 to 2024-12-31 inclusive 1,508 (two rows on each boundary day); from 2026-06-01 983; up to 2017-12-31 1,720; rows with a numeric score 11,027. Engineering reads the log file and the database for the ops-side checks.

## Cases

### TC-1 [high] An admin exports everything for their own company
Covers: Req #4, Req #7, Req #11
Story: As a company admin, when I start an export with no filters, I get a file of my own company's assessments and nobody else's.
Preconditions: Admin 2 signed out. No export in progress for Admin 2.
Steps:
1. Sign in as Admin 2 and open the Exports page from the home page.
2. Leave both dates blank and the status on "All", then click "Export CSV".
3. Look at the page that appears, then refresh it until the export shows as ready.
4. Note the Rows number in the history.
Expected: The page shows "Export started", a message saying exports can take a few minutes and to refresh, and a history row that starts as In progress and becomes Ready with a "Download CSV" link. Rows reads 15,790, the number of Company 02 assessments.
Also check: Another company's name or data appears nowhere on the page. The history shows only this company's exports.
Unit-tested: yes (UT-1, UT-10)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. Signed in as Admin 2, clicked Export CSV: saw "Export started.", the refresh message and an In progress row; after a refresh the row was Ready with Rows 15790 and a Download CSV link. No other company's data on the page.

### TC-2 [high] Another company's admin, or a signed-out visitor, cannot open an export
Covers: Req #4
Story: As an admin of another company, when I try to open a link to an export that is not mine, I am refused; and if I am signed out I am sent to sign in.
Preconditions: TC-1 done (an export of Company 02 exists and you know its link). Admin 3 signed out.
Steps:
1. While signed out, paste the link of the Company 02 export into the address bar.
2. Sign in as Admin 3, then paste the same link again.
3. Open the Exports page as Admin 3 and look at the history.
Expected: Signed out, you land on the sign-in page. As Admin 3 you see a "not found" page, not a file. Admin 3's history does not show Company 02's export.
Also check: The link works again for Admin 2 after signing back in.
Unit-tested: yes (UT-2)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. Signed out: the link went to the sign-in page. As Admin 3: HTTP 404 for Company 02's export (the development error page shows because this is dev mode; production shows a plain not-found). Admin 3's history showed only Admin 3's own exports.

### TC-3 [high] The file has only the allowed columns and no personal data
Covers: Req #8, Req #9, Req #12
Story: As a company admin, when I open an export file, I see only the six allowed columns and no emails, comments or raw answers.
Preconditions: TC-1 done: a Ready export of Company 02. A way to read the file (open the download, or the page-based read engineering offers).
Steps:
1. Open the Company 02 export file.
2. Read the first line (the column names).
3. Search the whole file for the "@" sign, and for the words "comments" and "answers".
4. Look at the status and score columns for a few rows, including rows where the score is empty.
Expected: The first line is exactly: assessment_id, assessment_date, created_at, status, score, employee_id. There is no "@", no "comments" and no "answers" anywhere. Status shows the stored text (for example "Complete " or "comp"). Score is either a plain number or empty; it is never text.
Also check: The number of data lines is 15,790. About 11,027 rows have a score.
Unit-tested: yes (UT-3, UT-5, UT-6)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. Read the file through the page (not saved): header exactly assessment_id,assessment_date,created_at,status,score,employee_id; 15790 data lines; no "@", "comments" or "answers"; 11027 rows with a score, all numeric; raw statuses such as "COMPLETE", "Complete " and "comp".

### TC-4 [high] Spreadsheet formulas are neutralised
Covers: Req #8
Story: As a company admin, when a status starts with a formula character, the file shows it as plain text so a spreadsheet cannot run it.
Preconditions: Engineering has created "Test Company X" with its own admin and four assessments with statuses "pending", "Done " (with a trailing space), "secret-only-here" and "=1+1". Test Company X's admin signed in.
Steps:
1. Sign in as Test Company X's admin and open Exports.
2. Start an export with no filters and refresh until Ready.
3. Open the file and find the row whose status begins with "=".
Expected: That status cell begins with an apostrophe (it reads '=1+1). The other three statuses are unchanged.
Unit-tested: yes (UT-4)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. Test Company X export: the status cell reads '=1+1 (leading apostrophe); the other three statuses unchanged.

### TC-5 [normal] The date range is inclusive and either end can be left blank
Covers: Req #5
Story: As a company admin, when I choose dates, I get the assessments on those days and nothing outside them.
Preconditions: Admin 2 signed in, nothing in progress.
Steps:
1. Start an export with From 2024-01-01 and To 2024-12-31. Open the file when Ready.
2. Start an export with only From 2026-06-01. Open the file when Ready.
3. Start an export with only To 2017-12-31. Open the file when Ready.
Expected: Step 1 gives 1,508 rows, with the first date 2024-01-01 and the last 2024-12-31, both included. Step 2 gives 983 rows, none before 2026-06-01. Step 3 gives 1,720 rows, none after 2017-12-31.
Also check: The history shows each export's From and To, with "any" for a blank end.
Unit-tested: yes (UT-7)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. From 2024-01-01 to 2024-12-31: 1508 rows, first 2024-01-01, last 2024-12-31. From 2026-06-01 only: 983 rows, earliest 2026-06-01. To 2017-12-31 only: 1720 rows, latest 2017-12-31. History shows "any" for a blank end. (Exports started by posting the form from the page rather than clicking, for speed.)

### TC-6 [normal] A start date after the end date is refused and the form still works
Covers: Req #5, Req #36
Story: As a company admin, when I choose a start date after the end date, I am told, nothing starts, and I can fix it and try again.
Preconditions: Admin 2 signed in, nothing in progress. Count the rows in the history first.
Steps:
1. Enter From 2025-02-01 and To 2025-01-01.
2. Click "Export CSV".
3. Look at the page and the history, then change From to 2025-01-01 and click "Export CSV" again.
Expected: A message "Start date is after the end date." appears, the history has no new row, and the Export button is clickable again (not stuck on "Starting export…"). The corrected request starts normally.
Unit-tested: yes (UT-8)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. From 2025-02-01 to 2025-01-01: message "Start date is after the end date." shown, history row count unchanged, button enabled and not stuck on "Starting export…". After fixing From to 2025-01-01 the export started and was Ready (3 rows).

### TC-7 [high] The status filter groups spellings and treats blanks as one choice
Covers: Req #5, Req #6
Story: As a company admin, when I pick a status, I get every row that status stands for, whatever its spelling.
Preconditions: Admin 2 signed in, nothing in progress.
Steps:
1. Open the Status list and read the choices.
2. Export with Status "complete". Open the file and look at the status column.
3. Export with Status "(no status)". Open the file and look at the status column.
4. Export with Status "n/a". Open the file and look at the status column.
Expected: The list shows one "complete", not "Complete" and "COMPLETE" as separate choices, plus "n/a" and "(no status)" once each. Step 2 gives 2,850 rows, all spellings of complete (for example "Complete ", "complete ", "COMPLETE"), and not "comp" or "done". Step 3 gives 1,304 rows whose status cells are all empty or blank. Step 4 gives 335 rows, all "n/a".
Unit-tested: yes (UT-7, UT-9)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. Status list had one "complete", "n/a" and "(no status)". complete: 2850 rows (COMPLETE 383, "Complete " 574, complete 1893; no comp or done). (no status): 1304 rows, all blank or empty. n/a: 335 rows, all n/a.

### TC-8 [normal] The status list shows only your own company's statuses
Covers: Req #6
Story: As a company admin, when I open the Status list, I see only statuses my company has used.
Preconditions: Test Company X exists as in TC-4. Admin 1 and Test Company X's admin available.
Steps:
1. Sign in as Test Company X's admin and read the Status list.
2. Sign out, sign in as Admin 1 and read the Status list.
Expected: Test Company X's list is exactly: =1+1, done, pending, secret-only-here (and no "(no status)"). "secret-only-here" does not appear in Admin 1's list. Admin 1's list has no repeated spellings.
Also check: If engineering adds a new status to Test Company X and you reload within 10 minutes, it is not listed yet (the list is kept for 10 minutes); after 10 minutes it appears. This extra check may be skipped.
Unit-tested: yes (UT-9)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. Test Company X's list: =1+1, done, pending, secret-only-here (no "(no status)"). The =1+1 option is correct because that status is stored; the plan's expected list omitted it and has been corrected. Admin 1's list had no "secret-only-here" and no repeated spellings. The optional 10-minute check was skipped.

### TC-9 [high] A very large export runs in the background with no row limit
Covers: Req #5, Req #7
Story: As the admin of the largest company, when I export all 200,000 assessments, the page stays responsive and I get every row.
Preconditions: Admin 1 signed in, nothing in progress.
Steps:
1. Open Exports, leave the filters empty and click "Export CSV".
2. As soon as the page appears, note the history row and the refresh message. Do not refresh for about 30 seconds and watch whether the page changes by itself.
3. Refresh until the export is Ready and note the Rows number.
Expected: The page appears straight away with an In progress row and the refresh message. It does not update by itself. After a refresh it shows Ready and Rows reads 200,000.
Also check: The file is about 10.8 MB.
Unit-tested: yes (UT-10, UT-11)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. Admin 1 export: In progress row and refresh message shown straight away; unchanged after 30 seconds without a refresh; after a refresh Ready, Rows 200000, file 10,821,705 bytes (about 10.8 MB), no "@". A timed request showed the start request returns in about 11 ms.

### TC-10 [normal] The button gives feedback and only one export can run at a time
Covers: Req #10, Req #36
Story: As a company admin, when I click Export, I see that it started and I cannot start a second one by mistake.
Preconditions: Admin 1 signed in, nothing in progress. This case is timing sensitive: the large export takes only a few seconds.
Steps:
1. Click "Export CSV" once and watch the button.
2. Straight away, before the first export is Ready, open Exports again and click "Export CSV" a second time.
Expected: After the first click the button is disabled and shows "Starting export…" until the page changes. The second click shows "An export is already in progress." and the history has only one new row.
Unit-tested: yes (UT-13)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. At submit the button was disabled and showed "Starting export…" (recorded by a listener). A second submit while the first ran showed "An export is already in progress." and added no row (the second attempt was sent by script, not a second mouse click).

### TC-11 [normal] The history shows the 20 newest exports of your own company
Covers: Req #7
Story: As a company admin, when I look at my exports, I see the 20 newest, newest first, and none from other companies.
Preconditions: Engineering has added 21 older finished exports for Test Company X (Rows 1 to 21) and one finished export for Company 01 with Rows 777777.
Steps:
1. Sign in as Test Company X's admin and open Exports.
2. Count the history rows and read the order.
3. Look for the number 777777.
Expected: Exactly 20 rows, newest first, the oldest of the 22 not shown. 777777 does not appear.
Unit-tested: yes (UT-10)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. As Test Company X's admin: exactly 20 history rows, newest first, Rows 21 down to 2 (the oldest, Rows 1, not shown); 777777 not present.

### TC-12 [high] A failed export shows only a plain message
Covers: Req #10
Story: As a company admin, when an export fails, I see that it failed and can try again, without any technical detail.
Preconditions: Engineering has made the storage folder unwritable so the file cannot be saved. Admin 5 signed in, nothing in progress.
Steps:
1. Start an export with no filters.
2. Refresh until the row is no longer In progress.
3. Read the row and the whole page.
4. After engineering restores the folder, click "Export CSV" again.
Expected: The row shows Failed with the words "Export failed, please try again" and no download link. No error text, file name or data appears anywhere. After the folder is restored a new export becomes Ready.
Also check: Engineering confirms the log has one line naming the export and the error type only, and no data.
Unit-tested: yes (UT-12)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. With the storage folder made unwritable: the row showed Failed with "Export failed, please try again", no download link, no error text or file names on the page. Log line: "ExportJob failed export=36 error=Errno::EACCES" only. After restoring the folder a new export became Ready (15790 rows).

### TC-13 [normal] An export stuck for over 30 minutes counts as failed
Covers: Req #10
Story: As a company admin, when an export never finishes, it eventually counts as failed so I can start a new one.
Preconditions: Engineering has created an In progress export for Admin 3 dated 31 minutes ago.
Steps:
1. Sign in as Admin 3 and open Exports.
2. Read that row, then click "Export CSV".
Expected: The old row shows Failed. The new export starts (no "already in progress" message).
Unit-tested: yes (UT-14)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. As Admin 3 the 31-minute-old In progress row showed Failed; a new export started with no "already in progress" message and became Ready.

### TC-14 [normal] An export older than 7 days is expired
Covers: Req #10
Story: As a company admin, when an export is older than a week, it shows as expired and its file is gone.
Preconditions: Engineering has created a Ready export for Admin 4 with a file, dated 8 days ago, and knows its link.
Steps:
1. Sign in as Admin 4 and open Exports.
2. Read that row.
3. Paste that export's link into the address bar.
4. After engineering runs the clean-up job, check again.
Expected: The row shows Expired with no "Download CSV" link. The link gives a "not found" page. After the clean-up the stored file is gone and the row still shows Expired.
Unit-tested: yes (UT-15)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. As Admin 4 the 8-day-old export showed Expired with no Download link; its link gave 404. After the clean-up job: the stored file was gone, state expired, row still Expired.

### TC-15 [high] The download is a plain CSV and storage links do not work
Covers: Req #11
Story: As a company admin, when I download an export it is a plain CSV file, and no public link to it exists.
Preconditions: TC-1 done.
Steps:
1. Click "Download CSV" on the Company 02 export and note the file name and type.
2. Type this into the address bar while signed out: `/rails/active_storage/blobs/redirect/test/export.csv`.
Expected: The file is named like assessments-export-N.csv, is plain text, and is not zipped. The address in step 2 gives a "not found" page.
Unit-tested: yes (UT-16)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. Checked through the page, not by saving a file: header attachment; filename="assessments-export-26.csv", type text/csv; plain text. Storage links /rails/active_storage/... returned 404 both signed in and signed out. A real click-to-save download was not done (permission not given).

### TC-16 [high] The log holds no personal data after the whole run
Covers: Req #12, Req #13
Story: As support, when I read the application log after exports (including a failed one), I find no emails, comments or raw scores.
Preconditions: TC-1 to TC-14 done. Engineering can read the dev log file.
Steps:
1. Engineering searches the log lines written during the run for the test admins' email addresses, the seeded email domain, the words "comments" and "answers", and the seeded comment sentences.
2. Engineering reads the log lines for the failed export (TC-12).
Expected: No matches in step 1 (the sign-in lines show the parameters as filtered). Step 2 shows only the export number and the error type.
Unit-tested: yes (UT-17)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. Searched the 3200 log lines written during the run for the seeded email domain, "comments", "answers", the seeded comment sentences, "synthetic note", "private" and the dev password: 0 matches. Sign-in parameters show [FILTERED]. The failed export logged only the export number and error type.

### TC-17 [normal] There is no emailing and no way to pick another company
Covers: non-goal: emailing an export (Req #37); non-goal: an export that takes a company identifier (Req #38)
Story: As a company admin, I find no option to email an export or to choose another company.
Preconditions: Admin 2 signed in.
Steps:
1. Look over the Exports page for any email option or company choice.
2. Add `?company_id=1` to the Exports address and load it, then start an export.
Expected: There is no email option and no company field. With the extra parameter the page still shows Company 02's history, and the new export is Company 02's (Rows 15,790).
Unit-tested: yes (UT-1)
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. The form has only from, to, status and the button; no email option and no company choice. With company_id=1 added to the address and to the request, the page and the new export were Company 02's (Rows 15790).

### TC-18 [normal] There is no automatic refresh and no "done" banner
Covers: non-goal: polling and a global done banner (Req #39)
Story: As a company admin, I only see an export finish when I refresh, and no banner follows me around.
Preconditions: Admin 1 signed in, an export just started (as in TC-9).
Steps:
1. Stay on the Exports page for about 30 seconds without touching it.
2. Go to the home page.
Expected: The row stays In progress until you refresh. The home page shows no banner about the export.
Status: passed
Result: Run by Claude in the built-in local browser (not a human tester), 2026-11-07; awaiting human confirmation. A started export stayed In progress on the page for 30 seconds with no automatic change, and only showed Ready after a refresh. The home page showed no banner.

## Open questions

| Question | Who decides | Blocks |
|---|---|---|
| Is a real browser download (saving the file to the Downloads folder) allowed? Until answered the file is read through the page, without saving it. | the author | TC-1, TC-3, TC-15 (file name check) |
| TC-10 depends on timing: the large export finishes in a few seconds. Accept a retry if the first attempt is too slow to catch? | the author | TC-10 |

## Not tested here

Req 1, 2 and 3: the scaffold; sign-in is used as a step only and was checked with TKT-1.
Req 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28 and 29: Task 2 (dashboard, score reader, performance); cases are appended when Task 2 is tested.
Req 31, 32, 33, 34, 40, 41, 42, 43 and 44: Task 3 (status normalisation); cases are appended when Task 3 is tested.
Req 35: README and SOLUTION.md deliverables; reviewed separately.
