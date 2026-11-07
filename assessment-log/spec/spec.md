# EPIC-1 (draft, no ticket yet): Safely extend the legacy Assessments module

Approved: yes
Sources read: OfferZen assignment PDF (3 pages, read 2026-11-07) and the same text pasted in `assessment-log/PROMPTS.md` (identical); this conversation (prompts 1 to 15); `origin/main` code at ec98c5a (scaffold only).
Not read: none. No tracker, wiki, chat or hosted documents were involved. Staging, production and APM data do not exist for this exercise.

## Goal and why
Company admins of a ten-year-old Rails app manage employee ergonomic and health assessments. This work adds a company-scoped CSV export, makes the dashboard faster and its score trustworthy, and standardises status values with a safe release plan. The data is health related and the assessments table is large, so privacy, tenant isolation and not stalling the app drive every choice. The repo has no domain code, so a small scaffold (tables, sign-in, large messy seed data, a baseline dashboard) is part of the work.

## Scope and non-goals
- In scope: scaffold (Req 1 to 3); async company-scoped export with two filters, redaction and a minimal TypeScript UI (Req 4 to 11, 36); a shared PII scrubber and log hygiene (Req 12 to 14); the score contract, report and dashboard (Req 15 to 21, 28); benchmarked performance work (Req 22 to 27); Ruby-side status validation, an assessor input screen, a change request with a cut-over date, a plan-only new-column backfill and a Heroku-style release and rollback plan (Req 29 to 34, 40 to 44); README, SOLUTION.md and demo outline (Req 35).
- Not in scope: emailing the CSV (Req 37, user, 2026-11-07); an insecure legacy export (Req 38, user, 2026-11-07); polling, a global done-banner, score gating or alerts after statuses are normalised, and staging or production measurement (Req 39, user, 2026-11-07); executing the historical backfill (Req 33, 42); a database check constraint (Req 30, user, 2026-11-07); the 4-hour timebox (user, 2026-11-07); third-party login (user, 2026-11-07).

## Decisions
Where several requirements decide one outcome: Req 15 (contract) decides what a valid score is; Req 16 decides how a missing one is shown; Req 28 says the export and dashboard then share the reader and supersedes Req 9.

| Req | Decision | Acceptance | Decided by | Source |
|---|---|---|---|---|
| 1 | Minimal data model incl. `assessment_date` and `admins` | Schema loads, tables and columns as listed | user, 2026-11-07 | brief; user |
| 2 | Plain email/password sign-in; company only from the session | Sign-in works; no company parameter honoured | user, 2026-11-07 | user |
| 3 | Seed ~500k assessments, ~20 companies, one ~200k, messy statuses and scores | Counts by query; every case present | user, 2026-11-07 | user |
| 4 | Export own company only | Two-company test; client company id ignored; cross-company download 404 | brief; user | brief §Task 1 |
| 5 | Two filters: `assessment_date` range and status | Inclusive UTC days; 422 on invalid; no row cap | user, 2026-11-07 | user |
| 6 | Status select = company's distinct stored values, trimmed and case-insensitive, nil/blank = "(no status)" | Grouping test; cached 10 min; no data change | user, 2026-11-07 | user |
| 7 | Async export with history table and refresh message | Row in progress, refresh within ~2 s, 20 most recent, no polling | user, 2026-11-07 | user |
| 8 | Allow-listed columns, no PII or free text, formula-injection guard | Exact header; no email/free text | user, 2026-11-07 | brief; user |
| 9 | Pre-Task-2 export reads only numeric top-level `score` | Numbers exported, everything else blank | user, 2026-11-07 | user |
| 10 | Failure, duplicate click, 7-day expiry | Generic failed text; one in progress; expired row | user, 2026-11-07 | user |
| 11 | Active Storage, plain CSV, S3-style in production | Documented; no zip | user, 2026-11-07 | user |
| 12 | One PII scrubber for export, logs and error logs | Single declaration drives filters, inspect, log formatter | user, 2026-11-07 | user |
| 13 | No sensitive values in export/dashboard logs | Log-grep test | user, 2026-11-07 | brief; user |
| 14 | Dashboard log hygiene | Same test on the dashboard | user, 2026-11-07 | brief |
| 15 | Score contract | Unit test table | user, 2026-11-07 | user |
| 16 | "Score not available"; status does not gate; reader never raises; no footnote | 200 with bad data | user, 2026-11-07 | user |
| 17 | Read-time only | `responses_json` unchanged by any run | user, 2026-11-07 | user |
| 18 | Contract in code comments and plain assumptions in SOLUTION.md | Comment block and section exist | user, 2026-11-07 | user |
| 19 | Read-only score report with 5 examples per case | Rake output covers every case | user, 2026-11-07 | user |
| 20 | Each score rule small and removable, counted in the report | Delete one rule, rest pass | user, 2026-11-07 | user |
| 21 | Dashboard: email, employee id, date, status, score; same filters as export | Own company only | user, 2026-11-07 | user |
| 22 | Baseline dashboard and benchmark method first | Numbers recorded before changes | user, 2026-11-07 | user |
| 23 | Pagination 50/page, no total count, safe params, stable order | Parameter and order tests; numbers | user, 2026-11-07 | user |
| 24 | Eager loading | Bullet clean; constant query count | user, 2026-11-07 | user |
| 25 | One composite index, concurrent | Valid index; EXPLAIN before/after | user, 2026-11-07 | user |
| 26 | One change per PR with measured results | Numbers per step; no unmeasured claims | user, 2026-11-07 | user |
| 27 | Page keeps working | Page 1 identical before/after (except fixed scores) | user, 2026-11-07 | brief |
| 28 | Export and dashboard share the contract reader | Rows agree | user, 2026-11-07 | user |
| 29 | Ruby-side validation: only the five canonical statuses, on create and when status changes; no alias mapping on write | Non-canonical and case/whitespace variants rejected; unrelated updates on dirty rows still succeed | user, 2026-11-07 | user |
| 30 | No database constraint (dropped) | No CHECK in any migration | user, 2026-11-07 | user |
| 31 | Mapping from a reviewed sheet of distinct values, kept as a versioned file | Plan in SOLUTION.md; unmapped stays NULL and blocks the switch | user, 2026-11-07 | user |
| 32 | Legacy column kept written; backup before the rename; restore is last resort | Rollback steps in SOLUTION.md | user, 2026-11-07 | user |
| 33 | Read-only status report (value, count, latest updated_at, mapped counts) | No write path for historical rows | user, 2026-11-07 | brief |
| 34 | Step-by-step Heroku-style release and rollback plan | Steps labelled live-safe or window, each with rollback | user, 2026-11-07 | brief |
| 35 | README, SOLUTION.md, demo outline | Fresh clone runs | user, 2026-11-07 | brief |
| 36 | Minimal TypeScript | `yarn typecheck` passes | user, 2026-11-07 | brief |
| 37 | Email of CSV out of scope | No mail code | user, 2026-11-07 | user |
| 38 | No insecure legacy export | Documented only | user, 2026-11-07 | user |
| 39 | Future work listed, not built | Future work section | user, 2026-11-07 | user |
| 40 | Change request and cut-over date; log-only before, reject on and after | Test on both sides of the date | user, 2026-11-07 | user |
| 41 | Assessor input screen: free-text baseline, then validated dropdown | Two versions in git history; empty save impossible | user, 2026-11-07 | user |
| 42 | Column migration described not implemented; dual-write; one owner of the column name | SOLUTION.md section; no migration in the repo | user, 2026-11-07 | user |
| 43 | Lock and responsiveness safeguards stated, with pause thresholds (lag > 5 s, lock wait > 2 s, latency > 1.5x baseline) | Each step has lock behaviour and mitigation in SOLUTION.md | user, 2026-11-07 | brief |
| 44 | A new assessment with no status defaults to pending | Test: default stored, non-canonical rejected | user, 2026-11-07 | user |

## Conflicts resolved
| What differed | Source A | Source B | Winner and why |
|---|---|---|---|
| Export approach | My recommendation: streaming | User, 2026-11-07: async because ten years of data and a slow dashboard | Async (Req 7). The user's reasoning about freezing and load stands |
| Date filter field | My proposal: `created_at` | User, 2026-11-07: an assessment can be scheduled and not completed | `assessment_date` (Req 5) |
| Status dropdown | My proposal: alias map shared with Task 3 | User, 2026-11-07: an alias list cannot stay current without write-side enforcement | Distinct stored values (Req 6); Task 3 later collapses them |
| Proportions such as 0.85 | Accepted contract scaled them to 85 | User, 2026-11-07: the user must be sure, not doubt the score; accepted "show not available" | Not scaled, shown as not available and counted (Req 15) |
| "May differ" footnote | My proposal | User, 2026-11-07: the user must not doubt the score | No footnote (Req 16); the call-out lives in code comments and SOLUTION.md |
| Missing score text | Earlier agreement: a dash | User, 2026-11-07: 'score not available' | "Score not available" (Req 16) |
| Index choice | User's first idea: separate indexes on company, status, date | Status filter is trimmed and case-insensitive, so a plain status index would not be used | One composite index, accepted by the user (Req 25) |
| Status writes | My proposal: map known aliases on write, add a NOT VALID check | User, 2026-11-07: prevent it in Ruby, the database is not responsible | Reject non-canonical in Ruby (Req 29), no database constraint (Req 30) |
| Backfill rollback | My proposal: a side table of old values | User, 2026-11-07: a new column kept as legacy_status | New column and legacy column (Req 32, 34) |
| Rename | My proposal: skip the rename, keep an alias | User, 2026-11-07: rename later to avoid permanent tech debt and because other readers exist | Alias first, rename in a low-traffic window (Req 34) |
| Export vs email | User raised email as an alternative | User, 2026-11-07: S3 route, email a nice-to-have | Stored file; email out of scope (Req 37) |

## Edge cases and failure behaviour
- Req 5: an invalid date, a start date after the end date, or an unknown status gives 422 and creates no export (amended 2026-11-07 during TKT-3 planning).
- Req 6: `Complete`, `complete `, `COMPLETE` group to one option; nil, empty and blank-only are one "(no status)" option; `n/a` stays separate.
- Req 9 and 28: a non-number score exports blank; a non-object `responses_json` exports blank.
- Req 10: a failed job shows a generic message; a second click is refused while one runs; an export in progress for more than 30 minutes counts as failed (amended 2026-11-07 during TKT-3 planning); files expire after 7 days.
- Req 15 and 16: strings with `%`, a decimal comma, alias keys and double-encoded JSON are handled; `1,234`, `N/A`, out-of-range numbers and proportions are not; any unexpected error in a row shows "Score not available" and the page stays up.
- Req 23: bad page values never return an error status; ties in date do not duplicate or skip rows.
- Req 29: validation runs only when status is set, so updating another field on a legacy row with a dirty status still works; a new record without a status becomes pending (Req 44).
- Req 34: rows written during the backfill are covered by writing both columns first; unmapped values keep the new column NULL and block the switch.

## Test seams
- Export: the create-export request, the background job, the history table and the download link, as one flow from the browser-facing endpoint. No existing tests exist (the repo has empty test folders).
- Dashboard: the dashboard page request for a company with filters, plus the score reader unit table for Req 15.
- Status: the model save path (mapper and validation) and the dry-run report output.
- Logs: a captured log from running the export and dashboard flows.

## Open questions
| Question | Who decides | Blocks which Req |
|---|---|---|
| none | | |

## Vocabulary
- Assessment date: the day an assessment is scheduled or done. Not the creation time.
- Canonical status: one of pending, in_progress, completed, needs_follow_up, archived.
- Legacy alias: an old status spelling such as comp or done.
- Normalisation (score): reading a stored score into a clean 0 to 100 integer at display or export time, without changing stored data.
- Proportion: a stored score strictly between 0 and 1 (for example 0.85). Treated as invalid because its scale is ambiguous.
- Legacy column: the old status column kept (as legacy_status) after the cut-over so rollback stays possible.
- Cut-over date: the date after which non-canonical statuses are rejected; before it they are only counted.
