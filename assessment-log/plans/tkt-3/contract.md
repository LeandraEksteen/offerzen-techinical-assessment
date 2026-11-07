# TKT-3 contract

Repos: offerzen-techinical-assessment
Approved: yes

## No contract items

All behaviour is inside this one Rails app. The export request page, the background job and the download are same-app. No API, event or config key is shared with another service.

## Boundaries checked and left unchanged

- Queue: `config/environments/production.rb` sets `queue_adapter = :solid_queue` with its own `queue` database; `config/environments/development.rb` sets no adapter, so Rails uses the in-process `:async` adapter; `config/environments/test.rb` sets none. Unchanged. The job takes only an id or record, as `ApplicationJob` (TKT-2) requires.
- Files: `config/storage.yml` defines `test` (Disk, `tmp/storage`) and `local` (Disk, `storage/`); `config/environments/{development,production}.rb` use `:local`, `test.rb` uses `:test`. Unchanged. Production's local disk is ephemeral on a Heroku-like host (documented, Req 11).
- Cache: development `:memory_store`, test `:null_store`, production `:solid_cache_store`. Unchanged; the status-options test swaps in a memory store.
- Recurring tasks: `config/recurring.yml` has only a `production` section (solid_queue's own cleanup). The PR adds one entry there for expiry; no other environment has a scheduler.
- CI: `.github/workflows/ci.yml` unchanged.
