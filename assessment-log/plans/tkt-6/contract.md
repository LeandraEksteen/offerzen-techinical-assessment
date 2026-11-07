# TKT-6 contract

Repos: offerzen-techinical-assessment
Approved: yes

## No contract items

All behaviour is inside this one Rails app. Eager loading is a query-shape change inside one page.

## Boundaries checked and left unchanged

- Dashboard: `app/controllers/dashboard_controller.rb` and `app/views/dashboard/show.html.erb` (read on origin/main): the controller gains a `preload`, the view reads the employee through a new column-limited association; filters, order, paging and the naive score are untouched.
- Models: `app/models/assessment.rb` keeps `belongs_to :employee` as it is (the export and everything else still use it); one extra association is added. `app/models/employee.rb` unchanged (its PII declaration only affects `inspect` and logs).
- Export: `app/services/assessment_csv_export.rb` does not read employees and is untouched.
- Benchmark tooling and snapshots: `lib/dashboard_benchmark.rb`, `lib/dashboard_probe.rb`, `assessment-log/benchmarks/dashboard-page1-baseline-*.txt` reused unchanged.
- Gemfile, migrations, indexes: untouched (the index is TKT-7).
- CI: `.github/workflows/ci.yml` unchanged.
