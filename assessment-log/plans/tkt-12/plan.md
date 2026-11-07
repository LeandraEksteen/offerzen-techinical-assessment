# TKT-12 plan: README, final SOLUTION.md, benchmarks, demo outline

Status: approved (open questions accepted, with one change) and built. Source ticket: `assessment-log/tickets/TKT-12.md`. Spec: `assessment-log/spec/` (Req 35, 18, 26, 39 from the ticket; Req 11 and Req 38 documentation owed by earlier tickets, see open question 10). Decisions this builds on: all of `DECISIONS.md` (D-001 to D-029).

Epic tree read: EPIC-1 children TKT-1 to TKT-11 merged (PRs 1 to 17 on main); TKT-12 (this) To Do. No comments on TKT-12.

## Why this matters
The deliverables of the take-home are a repo that a stranger can run, a SOLUTION.md that explains the design and trade-offs, and a 5 to 10 minute demo video. Today the repo's README is a title, SOLUTION.md does not exist (only two section drafts and a decision log), and the PROMPTS.md summary still says "planning phase, no application code yet". This ticket turns eleven merged tickets into the thing a reviewer actually reads. It also has to show the working method (prompts and decisions are the evidence), so the log stays and is made easy to find.

## Architecture overview
Documentation only, plus one small test file that stops the docs rotting. README.md is the "run it" page. SOLUTION.md is the "why" page, assembled from `DECISIONS.md`, the plans, `benchmarks/task-2-dashboard.md` and the two drafts, organised by the brief's three tasks, with one Future work section. `assessment-log/demo-outline.md` is the script for the video the author records. `PROMPTS.md` keeps every prompt verbatim and gets a refreshed summary at the top. Call path for a reviewer: README (run it) to SOLUTION.md (understand it) to `assessment-log/` (see how it was built).

## Requirements
- Req 35: README gets a fresh clone to a running app (PGPORT, seeding, job worker, sign-in); SOLUTION.md covers design, trade-offs, the async choice, score assumptions, benchmarks and the Task 3 plan; a demo outline exists in `assessment-log/`.
- Req 18 (doc half): SOLUTION.md states plainly that the score data shape is unknown, lists each assumption and the legacy issues covered, says displayed scores can differ from stored data, names a masked production copy as the ideal validation. (The code half, the reader's header comment, shipped in TKT-8.)
- Req 26 (doc half): the before and after note for each performance change with time and query count and why each step was chosen; no claim without a number.
- Req 39: a Future work section naming polling, a global done-banner, status-based score gating or alerts, and staging or production measurement; none implemented.
- Req 11 (doc half, owed by TKT-3): production needs S3-style storage because a local disk is ephemeral on a Heroku-like host; dev and test use disk.
- Req 38 (out of scope as code, doc half): SOLUTION.md describes the legacy export behaviour from the brief and which control addresses each point; no endpoint accepts a company identifier.

## Evidence from the repo (read on origin/main)
- `README.md` is one line (the title). `database.yml` defaults `PGPORT` to 5433 and sets `gssencmode: disable`. `Procfile.dev` runs the server and `yarn build --watch`. `bin/` has `setup`, `dev`, `ci`, `jobs`.
- Jobs: development uses Rails' default in-process adapter (no `queue_adapter` set in `development.rb`), production sets `:solid_queue` and `config/deploy.yml` sets `SOLID_QUEUE_IN_PUMA`. So "running the job worker" in development means the server process runs the export job; production needs `bin/jobs` or the Puma plugin (to be stated exactly, and checked in MC-1).
- Storage: Active Storage `:local` (Disk) in development and production, `:test` in tests; no S3 service is configured (Req 11 says document it).
- Seeded admins are `admin<N>@company-<N>.example.test`; the password is `AssessmentSeeder::DEFAULT_PASSWORD`, overridable with `SEED_ADMIN_PASSWORD`. The README names these and never prints the password.
- Rake tasks that exist (to be named in the docs): `assessments:seed`, `benchmark:dashboard`, `benchmark:explain`, `dashboard:snapshot`, `scores:report`, `statuses:report`.
- The numbers already exist: `assessment-log/benchmarks/task-2-dashboard.md` has the baseline, one section per change, and the results table (normal user 421 ms to 7 ms, largest company 58,019 ms to 6 ms, queries 1,414 to 4, 199,064 to 4); the export timing (3,767 ms to 2,552 ms for 200,000 rows) is in TKT-8's section; the rehearsal and report numbers are in `solution-drafts/status-backfill.md`.
- Screenshots exist for TKT-3 and TKT-5 only (`assessment-log/screenshots/`); TKT-9 and TKT-10 were checked with curl and have none.

## SOLUTION.md outline (the main deliverable)
1. **Summary and how to read this repo** (what was built, ticket-to-PR map, where the log is).
2. **Task 1: company-scoped export.** Tenant isolation (company only from the session, 404 across companies), the legacy-export table from the brief with the control for each point (Req 38), why asynchronous (the 10-year, 200,000-row case, with the export time), job and history, what is in the file (allow-list, no PII or free text, formula-injection guard), failure and expiry, storage (Req 11), the PII scrubber (one declaration drives parameter filters, `inspect`, the log formatter and the export guard), the minimal TypeScript, limits.
3. **Task 2: dashboard.** The baseline and how it is measured, then one subsection per change (pagination, eager loading, composite index built concurrently, score reader) each with before and after time and query count and why it was chosen, the results table, what is still slow (deep pages, the status list), log hygiene on the dashboard.
4. **The score assumptions (Req 18)**: from the TKT-8 draft, plainly that the shape is unknown, each assumption, legacy issues covered, displayed scores can differ from stored data, the report, and a masked production copy as the ideal check.
5. **Task 3: status.** The order (stop the bad data first), the Ruby rule and the cut-over date (D-028), the assessor screen as before and after, the change request outline, and the backfill, release and rollback plan from the TKT-11 draft (seven steps, labels, locks, thresholds, backup, recovery, rehearsal numbers).
6. **Security and privacy summary** (health data): one table of control per risk.
7. **Testing, CI and tooling** (suite size, rubocop, brakeman, bundler-audit, typecheck, the guard and doc tests, Bullet, rack-mini-profiler).
8. **Trade-offs and known limitations** (offset pagination, per-process count, per-company status cache, unknown score data, local not production numbers).
9. **Future work (Req 39)**: polling, a global done-banner, status-based score gating or alerts, staging and production measurement, plus keyset pagination, the three-column index option, S3 storage, email of the CSV, a masked production copy for the score rules, executing the backfill.
10. **Appendix**: index of decisions (D-001 to D-029) with one line each.

The two drafts are folded in, then removed so there is one source of truth (git history keeps them); references to them in the log are updated (open question 1).

## Changes required (single repo)

| File | Change | Complexity |
|---|---|---|
| `README.md` | Replace the title-only file with the run-it guide | Medium |
| `SOLUTION.md` (new) | The document above | High (main deliverable) |
| `assessment-log/demo-outline.md` (new, **not committed**: the author's own, excluded through `.git/info/exclude`) | Script for the 5 to 10 minute video: timed sections, what to show and say, pre-flight checklist, the data and logins to use, the questions a reviewer may ask | Medium |
| `assessment-log/PROMPTS.md` | Refresh the summary (planning and build, counts, outputs, how the build went); prompts untouched | Medium |
| `assessment-log/README.md` | Link SOLUTION.md, the demo outline, benchmarks and plans | Low |
| `assessment-log/tickets/*.md`, `EPIC-1.md` | Merged tickets (TKT-1 to TKT-11) and the epic to Done; TKT-12 In Review | Low |
| `assessment-log/solution-drafts/*` | Removed after folding in; log references updated | Low |
| `assessment-log/DECISIONS.md` | D-030: how the docs are organised | Low |
| `test/docs/docs_test.rb` (new) | The doc tests UT-1 to UT-6 | Low |
| `assessment-log/plans/tkt-12/state/claims-audit.md` (new) | Each number or claim in the docs with its source | Low |

No application code, migration or gem.

## Contract summary
None. Single-repo change; see `contract.md`.

## PR strategy
One PR, base `main`, branch `docs/TKT-12/readme-solution-demo`, title `TKT-12 | Docs: README, final SOLUTION.md, benchmarks, demo outline`. Yaml in `pr-strategy.yaml`.

## Test matrix

| ID | Req | Case | Type | Bucket | PR |
|---|---|---|---|---|---|
| UT-1 | 35 | Relative markdown links resolve | positive | unit | 1 |
| UT-2 | 35, 26 | Every `bin/rails <task>` named in the docs is a real rake task | positive | unit | 1 |
| UT-3 | 35, 18, 11, 38 | SOLUTION.md has the required sections | positive | unit | 1 |
| UT-4 | 39 | Future work names the four items and none exists in the code | negative | unit | 1 |
| UT-5 | 35 | README names PGPORT, seeding, the worker and sign-in and never contains the seeded password | edge | unit | 1 |
| MC-1 | 35 | Fresh clone follows the README to a running app, seed, sign-in, dashboard and a finished export | positive | manual | 1 |
| MC-2 | 26 | Claims audit: every claim has a number and a source | positive | manual | 1 |
| MC-3 | 11, 18, 26, 35, 38, 39 | Documents read against the requirements and the ticket's demo coverage list | positive | manual | 1 |

## Risks and mitigations
- **A README that was never run.** Mitigation: MC-1 follows it literally in a scratch clone with a throwaway database via `DATABASE_URL`, and every fix goes back into the README (or is reported if it needs a code change).
- **Numbers drift or get invented.** Mitigation: SOLUTION.md only quotes figures from the benchmarks file, the decisions or the drafts; the claims audit (MC-2) lists each with its source; local figures are labelled local (no production claim).
- **The seeded password leaking into the repo docs.** Mitigation: the README names the constant and env var only; UT-5 fails if the value appears in README.md or SOLUTION.md.
- **Duplicated truth** (drafts, decisions, SOLUTION.md saying the same thing differently). Mitigation: fold the drafts in and delete them; SOLUTION.md links to decisions by id instead of restating their rationale at length.
- **Doc rot** (renamed rake tasks, moved files). Mitigation: UT-1 and UT-2.
- **The PROMPTS.md summary describes the author.** Mitigation: it is drafted from the prompts themselves (quoted behaviours only) and shown for the author's review before the commit.
- **Fixing the app while "only documenting".** Mitigation: scope lists the setup files only for a bug the fresh-clone check finds; report first, change only with your OK.
- **Invariant writers:** none (no invariant introduced).

## Open questions (need your decision; recommendation first)
1. **Drafts.** Recommend folding `solution-drafts/score-reader.md` and `status-backfill.md` into SOLUTION.md and deleting them (one source of truth; git history keeps them), updating references in the log. Alternative: keep them as superseded notes. Accept deleting?
2. **README verification.** Recommend a scratch clone with `DATABASE_URL` pointing at a throwaway database, following the README literally; I report any setup bug before touching code. Accept?
3. **Seeded password.** Recommend the README names `AssessmentSeeder::DEFAULT_PASSWORD` and `SEED_ADMIN_PASSWORD` and never prints the value (and a test enforces it). Accept?
4. **Job worker.** Recommend documenting what is true: in development jobs run inside the Rails server process; in production run `bin/jobs` (or the `SOLID_QUEUE_IN_PUMA` Puma plugin as configured in `config/deploy.yml`) with S3-style storage. I only try running a separate worker locally if it works without config changes; otherwise the README says so plainly. Accept?
5. **Doc tests.** Recommend `test/docs/docs_test.rb` (links resolve, rake tasks named exist, required sections, Future work items, README facts, no password, demo length). Accept?
6. **Claims audit.** Recommend `state/claims-audit.md` in the plan folder listing each number and claim with its source. Accept?
7. **Demo outline.** Recommend `assessment-log/demo-outline.md`: about 9 minutes in timed sections (framing and method 1:00, architecture 1:30, Task 1 live 2:00, Task 2 numbers 2:00, Task 3 plan 1:30, trade-offs and what next 1:00), with a pre-flight checklist, exact logins (admin and company names, no password), and likely reviewer questions. You record it. Accept?
8. **PROMPTS.md summary.** Recommend rewriting the summary to cover planning and the build (counts, outputs, how the build went, what you caught), prompts untouched, shown to you before the commit. Accept?
9. **Ticket housekeeping.** Recommend marking TKT-1 to TKT-11 and EPIC-1's merged children Done and TKT-12 In Review in this PR. Accept?
10. **Documentation owed by earlier tickets.** Req 11 (S3) and Req 38 (legacy export controls) have no SOLUTION.md section yet because SOLUTION.md did not exist; recommend writing them here and adding Req 11 and 38 to this ticket's requirement list. Accept?
11. **Future work beyond Req 39.** Recommend also naming keyset pagination, the three-column index option, S3 storage, emailing the CSV, a masked production copy for the score rules, and executing the backfill, each marked "not done" with the reason. Accept?
12. **Screenshots.** Recommend no new screenshots (TKT-3 and TKT-5 have them; TKT-9 and TKT-10 were curl-checked); the demo is the visual. Accept, or do you want a few for SOLUTION.md?

## Out of scope
Recording the video (the author does), any application code change, executing the backfill, changing numbers or re-benchmarking (every figure quoted is already recorded).

## Estimated scope
About 7 files and 900 lines of prose (README about 120, SOLUTION.md about 350, demo outline about 120, PROMPTS summary about 40, log updates) and about 100 lines of test. Single PR.

## Critic pass
Not run as a separate agent: single repo, no contract items.

## Self-check
- Req 35, 18, 26, 39 (and the owed Req 11 and 38) land in PR 1 with UT-1 to UT-6 and MC-1 to MC-3. Documents cannot be unit-tested, so prose quality is checked by MC-2 and MC-3; structure and rot by UT-1 to UT-6.
- If open question 1 is answered "keep", the draft files stay and SOLUTION.md links to them instead of copying.

## Implementation notes (added after building)
- **Change from the plan, by the author:** the demo outline is for the author's own use and is not committed. It is written (about 9 minutes, timed, with a pre-flight list and likely questions) at `assessment-log/demo-outline.md`, excluded through `.git/info/exclude`; UT-6 was dropped (the file is not in the repo to test) and spec Req 35 was amended. Everything else in the plan was accepted as written.
- **MC-1 (fresh clone):** a scratch clone and a throwaway database (`DATABASE_URL`), then `bin/setup --skip-server`, the seed, the server, a curl sign-in, the dashboard and a finished export (2,001 CSV lines for company 1 of a 5,000-row seed). One trap found and documented, not fixed: `db:prepare` seeds 300 rows, then `assessments:seed` refuses to run and its message says "run db:reset first", which brings the small seed back. The README gives `db:drop db:create db:schema:load assessments:seed`. The misleading message is in `lib/assessment_seeder.rb` and is left alone (outside this ticket's scope).
- **Job worker:** the development environment has no queue database (Solid Queue's queue database is configured for production only), so a separate worker cannot run in development without a config change. The README says so plainly.
- **Two comment-only edits outside the documents:** `lib/status_report.rb` and `db/status_mapping.yml` pointed at the deleted draft file; they now point at SOLUTION.md. No behaviour changed.
- **The docs tests (UT-1 to UT-5 plus a numbers check)** found nothing broken on the first run apart from a missing `require "rake"` in the test itself. The suite is 208 tests.
- **CI claim corrected while writing:** the workflow does not run `yarn typecheck`; SOLUTION.md says so.

