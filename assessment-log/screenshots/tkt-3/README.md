# TKT-3 screenshots

Taken in the local browser while running the Task 1 acceptance test plan (`assessment-log/spec/test-plan.md`), against the seeded development database. All data is synthetic.

1. `01-exports-page.jpg`: the Exports page for Company 01: date range, status list and the history table.
2. `02-export-in-progress.jpg`: just after clicking "Export CSV" for the 200,000-row company: "Export started.", the refresh message, and an In progress row.
3. `03-export-ready.jpg`: after a refresh: the export is Ready (200000 rows) with a Download CSV link.
4. `04-date-validation-error.jpg`: a start date after the end date is refused with a plain message and nothing is created.
5. `05-failed-export-then-ready.jpg`: a failed export shows only "Export failed, please try again"; the next one succeeded (Company 05).
6. `06-expired-export.jpg`: an export older than 7 days shows Expired with no download link (Company 04).
