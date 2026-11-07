# TKT-5 contract

Repos: offerzen-techinical-assessment
Approved: yes

## No contract items

All behaviour is inside this one Rails app. Pagination is a same-app page change.

## Boundaries checked and left unchanged

- Dashboard: `app/controllers/dashboard_controller.rb` and `app/views/dashboard/show.html.erb` (read on origin/main) are changed only to add paging; the filters, the order and the naive score read stay.
- Filters: `Assessment.matching` (`app/models/assessment.rb`), `ExportFilters` and `StatusOptions` unchanged; the export (`app/services/assessment_csv_export.rb`) is untouched.
- Gemfile: no pagination gem is present (no pagy, kaminari or will_paginate); none is added.
- Benchmark tooling: `lib/dashboard_probe.rb`, `lib/dashboard_benchmark.rb`, `lib/tasks/dashboard.rake` (read on origin/main) are reused; only the scenario list changes.
- CI: `.github/workflows/ci.yml` unchanged.
