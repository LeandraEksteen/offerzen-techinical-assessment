# TKT-10 contract

Repos: offerzen-techinical-assessment
Approved: no

## No contract items

All behaviour is inside this one Rails app: a model validation, a default, one config value, and the TKT-9 screen's field. Nothing crosses a service boundary.

## Boundaries checked and left unchanged

- Seeder: `lib/assessment_seeder.rb` (read on origin/main) writes with `Assessment.insert_all`, which bypasses validations and defaults, so the dirty legacy statuses the benchmarks and the status report need stay exactly as seeded. `db/seeds.rb` only calls the seeder.
- Export and dashboard: `app/services/assessment_csv_export.rb`, `app/controllers/dashboard_controller.rb`, `app/services/export_filters.rb` read statuses and never write them; unchanged.
- `StatusOptions` (`app/services/status_options.rb`): still normalises whatever is stored for the filter list; unchanged. `StatusOptions.forget` is still called on a save.
- Sign-in and tenancy: `app/controllers/application_controller.rb` unchanged; the TKT-9 lookup through the admin's company stays.
- Database: no migration, no CHECK constraint (Req 30 dropped), no schema change.
- PII and logging: `lib/pii/`, `config/initializers/filter_parameter_logging.rb` unchanged; the new log line carries no status value and no email.
- CI: `.github/workflows/ci.yml` unchanged.
