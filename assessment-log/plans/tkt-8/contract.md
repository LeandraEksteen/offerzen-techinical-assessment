# TKT-8 contract

Repos: offerzen-techinical-assessment
Approved: yes

## No contract items

All behaviour is inside this one Rails app. The score reader is an internal service; the dashboard, the export and a rake task are its callers.

## Boundaries checked and left unchanged

- Dashboard: `app/controllers/dashboard_controller.rb`, `app/helpers/dashboard_helper.rb` (`stored_score`, the deliberate baseline) and `app/views/dashboard/show.html.erb` (read on origin/main) change only in how the Score cell is produced; filters, order, paging, preload and columns other than score are untouched.
- Export: `app/services/assessment_csv_export.rb` (read on origin/main) keeps its fixed six columns, batching, formula guard and PII column guard; only how the `score` cell is computed changes, and the export's header and column order stay exactly as they are.
- Stored data: `responses_json` is never written by any code path here (Req 17); no migration.
- Logging and PII: `lib/pii/` and `config/application.rb` (log formatter) unchanged; this ticket must add no log line carrying a score value.
- Seeder: `lib/assessment_seeder.rb` already produces every score shape; unchanged.
- Benchmarks: `lib/dashboard_benchmark.rb`, `lib/dashboard_probe.rb` and the snapshot tasks are reused; the committed baseline snapshots stay as the "before".
- CI: `.github/workflows/ci.yml` unchanged.
