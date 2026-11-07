# TKT-4 contract

Repos: offerzen-techinical-assessment
Approved: yes

## No contract items

All behaviour is inside this one Rails app. The dashboard is a same-app page; the benchmark and snapshot tasks run in-process.

## Boundaries checked and left unchanged

- Filter semantics: `app/services/export_filters.rb` and `app/services/status_options.rb` (read on origin/main) are reused as they are, so the dashboard and the export agree on the date range and the status grouping. Unchanged.
- Auth and tenancy: `app/controllers/application_controller.rb` (`require_admin`, `current_company`) unchanged; the dashboard finds rows only through `current_company`.
- Logging: `lib/pii/` and `config/application.rb` (log formatter) unchanged; the dashboard adds no new logging.
- CI: `.github/workflows/ci.yml` unchanged. The new gems sit in the `development` group only, so the test job does not load them.
- Load-test tooling: `hey` and `k6` are not installed on this machine; `ab` (ApacheBench) is at `/usr/sbin/ab`. See the plan's open questions.
