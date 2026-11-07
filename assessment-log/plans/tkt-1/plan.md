# TKT-1 plan: scaffold, data model, admin sign-in, large messy seed data

Status: plan, not yet approved. Source ticket: `assessment-log/tickets/TKT-1.md`. Spec: `assessment-log/spec/` (Req 1, 2, 3).

## Why this matters
The repo is a bare Rails scaffold with an empty schema. Every later ticket needs a company-scoped data model, a way for a company admin to sign in, and a large messy dataset to measure and test against. Without it the export, dashboard and status work cannot be demonstrated. The messy seed is also what makes Task 2's before and after real.

## Architecture overview
One Rails app, one PR. Four tables (companies, employees, assessments, admins). A plain session sign-in whose company comes only from the signed-in admin. A small `db/seeds.rb` that is safe for `bin/ci`, plus a separate rake task that generates about 500,000 deliberately messy assessments in batches.

## Requirements
- Req 1: minimal data model, including `assessment_date` and `updated_at`.
- Req 2: plain email/password sign-in; company only from the session.
- Req 3: large messy seed data (about 500k, about 20 companies, one about 200k, dirty statuses and score shapes).

## Changes required (single repo)

| Area | Change | Complexity |
|---|---|---|
| `Gemfile`, `Gemfile.lock` | Enable `bcrypt` (currently commented out; `bcrypt_pbkdf` in the lock file is an unrelated ssh dependency) | Low |
| Migrations | `companies(name)`; `employees(company_id, name, email)`; `assessments(company_id, employee_id, employee_email, status text null, responses_json jsonb null, assessment_date date not null, timestamps)`; `admins(company_id, email unique, password_digest)` | Low |
| Models | `Company`, `Employee`, `Assessment`, `Admin` (`has_secure_password`); associations and the validations from UT-2 only. No status or score logic (later tickets) | Low |
| Auth | `SessionsController` (new/create/destroy), `ApplicationController#current_admin`, `#current_company`, `require_admin` before action; sign-in view; placeholder home page showing the admin's company | Medium |
| Routes | `root` to home, `GET/POST /session`, `DELETE /session` | Low |
| `db/seeds.rb` | Small: a few companies, one admin each, a few employees and assessments. Must stay fast because `bin/ci` runs `db:seed:replant` in the test environment | Low |
| `lib/assessment_seeder.rb`, `lib/tasks/assessments.rake` | Seeder class and `assessments:seed` task: deterministic (fixed random seed), batched `insert_all` of 5,000, refuses to run in production, count configurable, defaults to 500,000 | Medium |
| Tests | UT-1 to UT-8 | Medium |
| Assessment log | Update TKT-1 status, decisions, prompts. Correct the PGPORT note (see Risks) | Low |

**Migration risk:** none for production (new tables on an empty database). The assessments table intentionally gets no secondary indexes (see Open questions).

### Seed design (what "messy" means)
- **Companies and volume:** 20 companies. Company 1 holds about 200,000 assessments (stands in for the ten-year customer); the other 19 share about 300,000.
- **Employees:** a few hundred per company, more for the big company; fake names and placeholder addresses on a reserved example domain. `assessments.employee_email` is a denormalised copy, as in the brief.
- **Dates:** `assessment_date` spread over ten years, some in the future (scheduled); `created_at` shortly before it; `updated_at` on or after `created_at`.
- **Status (stored text):** nil, empty string, blank-only, `n/a`, `complete`, `Complete `, `COMPLETE`, `comp`, `done`, `Done`, `pending`, `in_progress`, `needs_follow_up`, `archived`, with a realistic skew.
- **`responses_json` score shapes:** integer, float, float noise (`84.99999`), string `"85"`, `"85%"`, `"84,5"`, alias keys (`assessment_score`, `total_score`, `overall_score`), proportion (`0.85`), out of range (`150`, `-5`), `"N/A"`, `""`, null score, missing key, double-encoded JSON string, array, and a null `responses_json`. Plus per-question ratings and a free-text `comments` field containing placeholder personal details, so redaction tickets have something to catch.
- **Safety:** all values are synthetic. The seed refuses to run in production.

## Contract summary
None. Single-repo change; boundaries checked are listed in `contract.md`.

## PR strategy
One PR, base `main`, branch `feat/TKT-1/scaffold-data-model-signin-seed`, title `TKT-1 | Scaffold: data model, admin sign-in, large messy seed data`. Full yaml in `pr-strategy.yaml`.

## Test matrix

| ID | Req | Case | Type | Bucket | PR |
|---|---|---|---|---|---|
| UT-1 | 1 | Models and associations load; `assessment_date` required; `status` and `responses_json` nullable | positive | unit | 1 |
| UT-2 | 1, 2 | Assessment without date or company invalid; admin email unique and company required | negative | unit | 1 |
| UT-3 | 2 | Valid sign-in stores the admin; home shows their company | positive | unit | 1 |
| UT-4 | 2 | Wrong password creates no session | negative | unit | 1 |
| UT-5 | 2 | Unauthenticated request redirected to sign-in | negative | unit | 1 |
| UT-6 | 2 | A `company_id` parameter for another company does not change the company shown | edge | unit | 1 |
| UT-7 | 3 | Seed generator at small size: counts, one dominant company, every dirty status and score shape present | positive | unit | 1 |
| UT-8 | 3 | Seeding refuses to run in production | edge | unit | 1 |
| MC-1 | 3 | Run the 500k seed locally; record counts, distributions and time | positive | manual | 1 |
| MC-2 | 2 | Sign in, sign out and redirect in a real browser | positive | manual | 1 |
| MC-3 | 3 | `RAILS_ENV=test bin/rails db:seed:replant` (what `bin/ci` runs) finishes in seconds | edge | manual | 1 |

## Risks and mitigations
- **PGPORT note was wrong.** `TKT-1.md` and the spec's README requirement say the local Postgres listens on 5432. Checked now: the repo's own Postgres instance runs on 5433, which is the `database.yml` default, so no config change is needed. A separate system Postgres on 5432 requires a password. The PR corrects the note; the README (TKT-12) should say how to start a local Postgres on 5433.
- **`bin/ci` seeds in test.** `config/ci.rb` runs `db:seed:replant` in the test environment, so the default `db:seed` must stay small. Mitigated by the separate task and MC-3.
- **Seed runtime and memory.** 500k rows with a jsonb column. Mitigated by batched `insert_all` (5,000 per batch); time recorded in MC-1.
- **Adding a gem.** `bcrypt` is a new dependency. Mitigated by `bin/bundler-audit` in the PR checks.
- **Dev password in the seed file.** The seed uses a test password from `SEED_ADMIN_PASSWORD` with a documented dev default, refuses to run in production, and the value is never echoed in logs or the PR.
- **Foreign keys without indexes.** Assessments keep foreign keys but no indexes on them (see Open questions); inserts are checked per row, which is slower but fine at this size.

## Open questions (need your decision)
1. **Employee email.** `employees` gets its own `email` as well as `assessments.employee_email` (the brief's legacy copy). Task 2's baseline needs the dashboard to read the employee record to show the N+1; the brief does not say which of the two emails the page reads. Confirm.
2. **Indexes on assessments.** Create `assessments` with no indexes beyond the primary key, so the Task 2 baseline reflects a legacy table, and record that in DECISIONS.md. Confirm.
3. **New gem.** Approve enabling `bcrypt`.
4. **Placeholder home page.** After sign-in the admin sees a minimal page naming their company and a sign-out link. Later tickets replace it with real pages. Confirm.

## Out of scope
Any export, dashboard, status or score logic; roles, signup, password reset, third-party login; the README beyond a note (TKT-12).

## Estimated scope
About 15 to 20 files, about 600 lines including tests and the seed generator. Within the single-PR size guideline.

## Critic pass
Not run as a separate agent: single repo, no contract items, small scope. The lint and the self-check below stand in.

## Self-check
- Every active requirement (1, 2, 3) lands in PR 1 and has at least one unit case and, for Req 3 volume, a manual case.
- No behaviour decision lives only in this plan: the schema detail (employee email, no indexes) is raised as open questions and will be recorded in DECISIONS.md.

## Implementation notes (added after building)
- Scope grew by one path: the seeder lives in `lib/assessment_seeder.rb` (autoloaded), so the PR scope is `lib/` rather than only `lib/tasks/`.
- Added: login rate limiting (`rate_limit`, 10 attempts per 3 minutes) on sign-in; the seeder silences SQL logging because bulk inserts otherwise log every email and response body; seeder tests clear tables first because `bin/ci` leaves seeded data in the test database.
- Results: see the 2026-11-07 comment in `tickets/TKT-1.md` (MC-1 to MC-3 and check outputs).
