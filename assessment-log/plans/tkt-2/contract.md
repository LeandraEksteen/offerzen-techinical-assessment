# TKT-2 contract

Repos: offerzen-techinical-assessment
Approved: yes

## No contract items

All behaviour is inside this one Rails app. Logging, parameter filtering and job enqueueing are internal.

## Boundaries checked and left unchanged

- Logger setup: `config/environments/production.rb` line 38 builds its own `ActiveSupport::TaggedLogging.logger(STDOUT)`, which bypasses `config.log_formatter`. The PR changes this line (internal wiring, not a boundary); development and test use the default logger, which does honour `config.log_formatter`.
- Parameter filtering: `config/initializers/filter_parameter_logging.rb` already filters `:email`, `:passw`, `:token` and similar. Kept as is; model declarations add to it.
- CI: `.github/workflows/ci.yml` unchanged.
- Jobs: `app/jobs/application_job.rb` is the only job class; no jobs exist yet (TKT-3 adds the export job).
