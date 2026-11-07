# TKT-9 contract

Repos: offerzen-techinical-assessment
Approved: no

## No contract items

All behaviour is inside this one Rails app: a new controller, view and route, one link on the dashboard, one small method on `StatusOptions`. Nothing crosses a service boundary.

## Boundaries checked and left unchanged

- Sign-in and tenancy: `app/controllers/application_controller.rb` (read on origin/main): `require_admin` and `current_company` are reused as they are; no new role, no change to sessions.
- Dashboard: `app/controllers/dashboard_controller.rb` and its query are untouched; `app/views/dashboard/show.html.erb` gains one "Edit status" link per row (it needs only the id the query already selects).
- Status filter list: `app/services/status_options.rb` keeps its cache and normalisation; it gains one method that forgets a company's cached list.
- Model: `app/models/assessment.rb` stays deliberately unvalidated for status (validation is TKT-10, Req 29); no migration, no schema change.
- Export and score reader: `app/services/assessment_csv_export.rb`, `app/services/score_reader.rb` unchanged.
- Logging and PII: `lib/pii/`, `config/application.rb`, `config/initializers/filter_parameter_logging.rb` unchanged.
- CI: `.github/workflows/ci.yml` unchanged.
