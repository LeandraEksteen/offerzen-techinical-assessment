# TKT-11 contract

Repos: offerzen-techinical-assessment
Approved: no

## No contract items

All code is inside this one Rails app: a read-only report class and rake task, a mapping loader, and a draft mapping file. The release and rollback plan is a document; it executes nothing. Heroku, the database and the assessor-side front end are described in the plan, not called.

## Boundaries checked and left unchanged

- Status writes: `app/models/assessment.rb` (read on origin/main): the TKT-10 rule, `STATUSES` and the date switch are unchanged. The report and the mapping reuse `Assessment::STATUSES`.
- Raw SQL naming the status column: `app/services/status_options.rb` (`NORMALISED_SQL`) is the only place; unchanged, and a guard test is added.
- Dashboard, export, filters: `app/controllers/dashboard_controller.rb`, `app/services/assessment_csv_export.rb`, `app/services/export_filters.rb` read statuses only; unchanged.
- Seeder: `lib/assessment_seeder.rb` keeps writing dirty statuses with `insert_all` (the report needs them); unchanged.
- Schema and migrations: `db/schema.rb`, `db/migrate/`: no migration is added (the new column is plan only, Req 42); no CHECK constraint (Req 30 dropped).
- Existing reports: `lib/score_report.rb` and `lib/tasks/dashboard.rake` are the pattern copied (read-only, batched by id); unchanged.
- PII and logging: `lib/pii/` unchanged; the report scrubs through `Pii::Scrubber`.
- CI: `.github/workflows/ci.yml` unchanged.
