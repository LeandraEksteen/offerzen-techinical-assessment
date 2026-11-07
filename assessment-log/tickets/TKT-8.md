---
key: TKT-8
type: Task
title: Task 2: score reader, shared by dashboard and export, plus score report
status: In Review
parent: EPIC-1
updated: 2026-11-07T08:28:15Z
---

## Description
**Context:** The displayed score is sometimes blank or wrong. The data shape is unknown, so a documented contract reads the score at display and export time only.

**Scope:** The score reader per the contract (key order, parsing, range, proportions invalid, round half up); 'Score not available' in the UI and blank in the CSV; never raises; read-time only (stored JSON never rewritten); small removable rule units with tests; a read-only report task printing per case counts and 5 examples (assessment id, raw token, result); a code comment block summarising the contract; dashboard log hygiene test (Req 14); the export switched from the minimal numeric read to this reader.

**Not in scope:** Rewriting stored data, gating the score on status, any alert or error log for missing scores (Req 39), key drift beyond the four listed keys, scales such as 1 to 5 or 0 to 10.

**Depends on:** TKT-3, TKT-4

**Spec requirements:** Req 14, Req 15, Req 16, Req 17, Req 18, Req 19, Req 20, Req 28 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- SOLUTION.md must say plainly that the data shape is unknown, list each assumption, state that displayed scores can differ from stored data, and name a masked production copy as the ideal validation (finished in TKT-12).
- No footnote on the dashboard (author decision).

## Acceptance criteria
- Req 14: Dashboard request logs show the filter parameter names but not employee email or score values; satisfied by the same test as Req 13 run against the dashboard.
- Req 15: A reader returns the score as an integer 0-100 or nil: it takes the first valid value from the top-level keys score, assessment_score, total_score, overall_score in that order and never combines them; accepts numbers and strings (trimmed, trailing % stripped, a single decimal comma read as a point); ambiguous text such as '1,234', 'N/A' or empty is invalid; values below 0 or above 100 are invalid; a value strictly between 0 and 1 is NOT scaled and is invalid (counted separately); rounds half up. A unit test table covers each case, including a non-hash or nil responses_json.
- Req 16: A dashboard row with an invalid or missing score renders 'Score not available' (CSV: blank) and the page returns 200; a pending and a completed row with the same valid score both show it; the reader never raises - an unexpected error in one row is rescued, logged with only the error class and assessment id, and that row shows 'Score not available'; there is no footnote saying scores are normalised.
- Req 17: No code path writes to responses_json; a test records responses_json before and after loading the dashboard and running the export and report and finds it unchanged.
- Req 18: The score reader file begins with a comment block stating the key order, parsing rules, range rule and limitations; SOLUTION.md has a section stating plainly that the data shape is unknown, listing each assumption and the known legacy issues covered, noting that displayed scores can differ from stored data, and naming a masked production copy as the ideal validation.
- Req 19: A rake task scans assessments in batches without writing and prints, per case (valid as-is, string converted, percent stripped, decimal comma, alias key used, proportion rejected, other invalid, missing), a count and 5 examples each of assessment id, raw score token and result; it prints nothing else from the JSON; running it on the seed finishes and shows every case.
- Req 20: Each rule (key alias, percent strip, decimal comma, range, proportion) is a separate small unit with its own test; the report counts hits per rule; deleting one rule and its test leaves the others passing.
- Req 28: After Task 2, the export score column and the dashboard score come from the same reader; for every seeded row the two agree; the export shows a blank where the dashboard shows 'Score not available'.

## Definition of done
- PR links this ticket (`TKT-8` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
- 2026-11-07 implementation: `ScoreReader` (contract in its header comment, rules as removable units, never raises), `Assessment.with_score_candidates` and `#score_outcome`, `DashboardHelper#displayed_score` ("Score not available", per-row rescue logging only the error class), the CSV export reading the same reader (blank when no score), and `scores:report` (`ScoreReport`, read-only, tokens printed only if numeric or a placeholder word). Candidates are read in SQL so free text never reaches Ruby. Tests: reader table and rule-removal tests, dashboard/export agreement for every seeded shape, read-only check, log hygiene, report tests; 152 runs, 0 failures; rubocop, brakeman and bundler-audit clean.
- 2026-11-07 measurements (`assessment-log/benchmarks/task-2-dashboard.md`, "After the score reader"): page 1 unchanged at 6-7 ms and 4 queries; 200,000-row export median 2,552 ms (was 3,767); page-1 snapshots differ from baseline only in the score column (19 and 16 of 50 rows); Bullet log empty; report on 500k seed: 81.0% shown with a score, 10.5% missing, 3.2% proportions rejected, 5.3% other invalid.
