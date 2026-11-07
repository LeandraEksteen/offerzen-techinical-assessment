# TKT-12 contract

Repos: offerzen-techinical-assessment
Approved: no

## No contract items

Documentation and one small test file. No application behaviour changes and nothing crosses a service boundary.

## Boundaries checked and left unchanged

- Application code: `app/`, `lib/`, `config/`, `db/` are read to document them and are not changed. If the fresh-clone check finds a setup bug (`bin/setup`, `config/database.yml`, `db/seeds.rb`, `Procfile.dev`), it is reported first and fixed only with your OK.
- Existing drafts: `assessment-log/solution-drafts/score-reader.md` and `status-backfill.md` (read on origin/main) are folded into SOLUTION.md; the score reader's own header comment (`app/services/score_reader.rb`) already carries the contract for Req 18 and is unchanged.
- Benchmarks: `assessment-log/benchmarks/task-2-dashboard.md` and its snapshot and report files are the source of every number; unchanged except for a pointer line.
- Spec and tickets: `assessment-log/spec/` is unchanged; ticket status lines are updated (merged tickets to Done).
- CI: `.github/workflows/ci.yml` unchanged.
