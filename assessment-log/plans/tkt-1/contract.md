# TKT-1 contract

Repos: offerzen-techinical-assessment
Approved: yes

## No contract items

All behaviour is inside this one Rails app. No endpoint, event or config key crosses a service boundary. The sign-in form is a same-app page, not an API.

## Boundaries checked and left unchanged

- Database config: `config/database.yml` (read on origin/main) unchanged. Defaults to `PGPORT` 5433, which matches the repo's own local Postgres.
- CI: `.github/workflows/ci.yml` (read on origin/main) unchanged. It runs rubocop, brakeman, bundler-audit, `bin/rails db:test:prepare test`.
- `config/ci.rb` (`bin/ci`) runs `db:seed:replant` in the test environment, so `db/seeds.rb` must stay small and fast. The 500k seed is a separate task.
