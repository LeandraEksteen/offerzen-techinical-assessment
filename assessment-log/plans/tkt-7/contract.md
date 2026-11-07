# TKT-7 contract

Repos: offerzen-techinical-assessment
Approved: yes

## No contract items

All behaviour is inside this one Rails app and its database. A new index is a database-side change; no endpoint, event or config key is shared with another service.

## Boundaries checked and left unchanged

- Queries that use the index: `app/controllers/dashboard_controller.rb` (read on origin/main) already filters by company and orders by `assessment_date DESC, id DESC`; unchanged. `Assessment.matching` (`app/models/assessment.rb`) unchanged.
- Export: `app/services/assessment_csv_export.rb` batches by id; unchanged.
- Status options: `app/services/status_options.rb` unchanged (its DISTINCT query is not served by this index; see the plan).
- Schema: `db/schema.rb` currently shows `assessments` with no secondary index; the PR adds one entry.
- Existing test: `test/models/assessment_test.rb` asserts the table has no secondary index; the PR changes that test (the index is now intended).
- Deployment: `Procfile`-style release phase is not in the repo (the repo ships a Kamal config, not a Heroku one); the Heroku-like rollout is documented in SOLUTION.md only.
- CI: `.github/workflows/ci.yml` unchanged. It loads `db/schema.rb` into the test database, where the index is created without `CONCURRENTLY` (fine for an empty table).
