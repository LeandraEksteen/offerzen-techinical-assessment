---
key: TKT-1
type: Task
title: Scaffold: data model, admin sign-in, large messy seed data
status: Done
parent: EPIC-1
updated: 2026-11-07T08:46:11Z
---

## Description
**Context:** The repo is a bare Rails scaffold with an empty schema. The tasks need a small domain model, a way for a company admin to sign in, and a large messy dataset to measure against.

**Scope:** Tables and models for companies, employees, assessments (with `assessment_date` and `updated_at`) and admins; plain email/password sign-in form with `has_secure_password`; a seed task that builds about 500,000 assessments across about 20 companies (one about 200,000) in batches, with every dirty status and score shape the later tickets handle.

**Not in scope:** Any export, dashboard, status or score logic. No signup, password reset, roles or third-party login.

**Depends on:** none

**Spec requirements:** Req 1, Req 2, Req 3 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- `config/database.yml` defaults `PGPORT` to 5433, which matches the repo's own local Postgres instance (checked 2026-11-07; an unrelated system Postgres on 5432 needs a password). No config change is needed; the README (TKT-12) explains how to start Postgres on 5433.
- Decide at build time whether `assessments.company_id` gets the default foreign-key index. A single-column index would make the Task 2 baseline look better than a legacy table; the plan is to create it without that index so the baseline is honest, and record the choice in DECISIONS.md. Confirm with the author when building.
- `status` is nullable text with no constraint; `responses_json` is jsonb.

## Acceptance criteria
- Req 1: Database has companies, employees (company_id), assessments (company_id, employee_id, employee_email, status text nullable, responses_json jsonb, assessment_date date NOT NULL, created_at, updated_at) and admins (company_id, email, password digest); schema loads and the test suite boots.
- Req 2: Signing in with a seeded admin works; no third-party login exists; every export and dashboard request derives the company from the signed-in admin, never from a request parameter; unauthenticated requests are redirected to sign-in.
- Req 3: A seed task creates about 500,000 assessments across about 20 companies, one company holding about 200,000; statuses include nil, empty string, blank-only, 'n/a', complete, comp, done, pending, in_progress, needs_follow_up, archived and mixed case/whitespace variants; responses_json includes every score shape named in Req 15 plus free text; counts verifiable with a query.

## Definition of done
- PR links this ticket (`TKT-1` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
- 2026-11-07 implementation: 4 migrations, 4 models, sign-in/sign-out and a placeholder home page, `AssessmentSeeder` plus `assessments:seed`, small `db/seeds.rb`, 23 tests (UT-1 to UT-8 and extras). Checks: `bin/rails test` 23 runs 0 failures; `bin/rubocop` clean; `bin/brakeman` 0 warnings; `bin/bundler-audit` clean; `yarn typecheck` clean. MC-1: 500,000 assessments seeded in about 56 seconds (270 MB table, primary key only); company 1 holds 200,000, the other 19 hold 15,789 or 15,790 each; every status variant and score shape present; dates 2016-11-09 to 2027-01-06 with 8,158 scheduled in the future. MC-2: sign-in, wrong password, company parameter ignored, sign-out and redirect verified with curl against a local server (not a real browser). MC-3: `RAILS_ENV=test bin/rails db:seed:replant` takes about 1 second. Finding: the seed's bulk inserts logged full SQL (emails, responses) to development.log, so the seeder now silences SQL logging and a test covers it.
