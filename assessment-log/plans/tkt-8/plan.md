# TKT-8 plan: score reader, shared by the dashboard and the export, plus score report

Status: approved and built. Source ticket: `assessment-log/tickets/TKT-8.md`. Spec: `assessment-log/spec/` (Req 14 to 20, 28). Decisions this builds on: D-013 (the score contract), D-014 (read-time only), D-015 (status does not gate), D-016 (no footnote), D-021 (the export keeps free text out of Ruby).

## Why this matters
The brief says the score admins see is "sometimes blank or obviously off" and the shape of the stored data is unknown. Today the dashboard shows whatever sits in the top-level `score` key (so `"85%"`, `0.85` and `150` appear as they are) and the export emits only a JSON number. This ticket replaces both with one documented, tested reader that turns a stored score into a clean 0 to 100 whole number, or says plainly that none is available. It is the one change in Task 2 that alters what a person sees, so the evidence for it matters more than for the speed tickets.

## Experiments run for this plan (throwaway prototype of the contract, 500,000 seeded rows, aggregates only)
The prototype is in `state/prototype-reader.rb`; outputs in `state/seed-case-counts.txt` and `state/seed-edge-counts.txt`. The seed is deliberately messy, so these are not forecasts for real data; they show what each rule does.

| Outcome under the proposed contract | Rows | Share |
|---|---|---|
| **Shown** (a clean 0 to 100 score) | **404,867** | **81.0%** |
| of which stored exactly as a valid number under `score` | 277,226 | 55.4% |
| of which rounded (decimals, float noise such as 84.99999, half values) | 42,580 | 8.5% |
| of which taken from an alias key (`assessment_score`, `total_score`, `overall_score`) | 31,973 | 6.4% |
| of which a number stored as a string (`"85"`) | 26,415 | 5.3% |
| of which a percent sign stripped (`"85%"`) | 15,961 | 3.2% |
| of which a decimal comma read as a point (`"84,5"`) | 10,712 | 2.1% |
| **Score not available** | **95,133** | **19.0%** |
| no candidate key present (object without a score key 42,176; root is a JSON string 5,202; root is null 2,738; root is an array 2,635) | 52,751 | 10.6% |
| a proportion strictly between 0 and 1 (not scaled) | 16,038 | 3.2% |
| text that is not a number (`"N/A"`, empty) | 15,817 | 3.2% |
| out of range (below 0 or above 100) | 10,527 | 2.1% |

Other evidence:
- **Key used:** `score` 372,894 rows; `assessment_score` 16,076; `total_score` 10,669; `overall_score` 5,228.
- **More than one candidate key present:** 10,597 rows; the first present key was always valid, so **"first present" and "first valid" give the same answer on this seed** (0 rows differ). The contract says "first valid", which only matters on real data.
- **Edge strings in the seed:** none with a space before `%`, none with a comma followed by exactly three digits, no booleans; three values exactly 0 or 1.
- **Cost of where the candidates are read** (largest company, 200,000 rows): reading the whole `responses_json` takes 1,726 ms; reading only the four candidate keys in SQL takes 544 ms, about 3.2 times less, and keeps the free-text comments out of Ruby. The Ruby reader itself takes 883 ms for all 500,000 rows (about 0.35 s for 200,000).

## What the spec assumed that the evidence or the code does not support
1. **"Ambiguous text such as `1,234`" has no definition.** A bare decimal-comma rule would read `1,234` as 1.234, a valid score of 1. The plan defines it: a comma followed by exactly three digits could be a thousands separator and is invalid; a comma followed by one or two digits is a decimal comma (`84,5`). The seed has none of these, so the rule is a guess about legacy data (Open question 2).
2. **The dashboard loads the whole `responses_json` today** (all assessment columns, including the large one with the free-text comments). Reading the four candidate keys in SQL fixes that as a side effect.
3. **JSON numbers arrive in Ruby as Integer or Float,** and PostgreSQL's numeric type can exceed both; a huge number is simply out of range. JSON booleans and nested objects are not numbers and are invalid (not in the seed).
4. **0 and 1 are valid scores** (only values strictly between them are rejected); three seeded values are exactly 0 or 1.
5. **The report needs the raw token to eyeball accuracy, but a token can be arbitrary free text** typed into the score key. Printing it could leak personal data into a terminal or a committed file (Open question 4).
6. **Req 28 supersedes Req 9:** the export's score cell was "a JSON number or blank"; it becomes "the reader's result or blank".

## Architecture overview
A `ScoreReader` takes the four candidate values and returns an outcome: the score (a whole number 0 to 100, or nothing), which key it came from, which rules changed it, and why there is none. The candidate values come from SQL (`responses_json->'score'` and so on), built from one constant list of keys, so a non-object root simply yields nothing and free text never leaves the database. The dashboard and the export both call the reader, so they cannot disagree. A read-only report task runs the reader over all rows and counts the cases and rules. Stored data is never written.

## The contract (proposed; to go as a comment block at the top of the reader and into SOLUTION.md)
1. **Where:** only the top-level keys `score`, `assessment_score`, `total_score`, `overall_score`, in that order. The first one that holds a valid value wins; values are never combined or averaged. A non-object root (string, array, null) has no keys and gives no score.
2. **What counts as a number:** a JSON number, or a string that is, after trimming, digits with an optional single `.` or `,` decimal part and an optional `%` (a space before the `%` is allowed): `"85"`, `"85%"`, `"85 %"`, `"84,5"`, `"84.5"`. Anything else is not a number: `"N/A"`, empty, `"85 out of 100"`, `"1.234,5"`, booleans, objects and arrays. A comma followed by exactly three digits (`"1,234"`) is ambiguous and invalid.
3. **Range:** 0 to 100 inclusive. Below 0 or above 100 is invalid. A value strictly between 0 and 1 (for example `0.85`) is **not** scaled and is invalid, counted separately, because it could mean 0.85 or 85.
4. **Rounding:** half up to a whole number (84.5 becomes 85, 84.4999 becomes 84, 84.99999 becomes 85).
5. **Outcome:** a whole number 0 to 100, or nothing (shown as "Score not available" on the dashboard, blank in the CSV). Status never matters.
6. **Known limitation:** scales such as 1 to 5 or 0 to 10 cannot be told apart from low percentages and are read as percentages.

## Design

| Piece | What it does |
|---|---|
| `app/services/score_reader.rb` | The reader. `KEYS` is the one list of keys. Each rule is a small separate unit (key order, scalar only, string to number, percent sign, decimal comma and its ambiguity check, range, proportion, rounding) held in a named list, so a reader can be built without one rule in tests and a rule can be deleted with its test. Returns an outcome with `score`, `key`, `rules` and `reason`. Never raises (any unexpected error inside gives "no score"). A comment block at the top states the contract and its assumptions. |
| `Assessment` | A scope `with_score_candidates` that selects `responses_json->'<key>'` for each key in `ScoreReader::KEYS` (aliased), and `#score_outcome` that feeds them to the reader. |
| Dashboard | The controller selects only the columns the page shows plus the candidates (no whole `responses_json`). `DashboardHelper#stored_score` becomes `displayed_score`: the reader's score or "Score not available". A per-row rescue logs only the error class and the assessment id and shows "Score not available". |
| Export | `AssessmentCsvExport` plucks the same candidates and writes the reader's score or blank, replacing its numeric-only SQL; header, column order, batching and the formula and PII guards are unchanged. |
| `lib/score_report.rb` + `scores:report` | Read-only. Scans in batches; prints per-case counts (valid as is, string converted, percent stripped, decimal comma, alias key used, proportion rejected, other invalid, missing, with a note of how many missing rows have a non-object root) and per-rule hit counts, with up to 5 examples per case: assessment id, the raw token and the result. Tokens are never raw free text (Open question 4). |
| `assessment-log/solution-drafts/score-reader.md` | Draft of the SOLUTION.md section (Req 18): the data shape is unknown, each assumption, the legacy issues covered, displayed scores can differ from stored data, the scale limitation, and a masked production copy as the ideal validation. TKT-12 assembles SOLUTION.md. |

## Changes required (single repo)

| File | Change | Complexity |
|---|---|---|
| `app/services/score_reader.rb` | The reader and its rules | Medium |
| `app/models/assessment.rb` | Candidate scope and `score_outcome` | Low |
| `app/controllers/dashboard_controller.rb`, `app/helpers/dashboard_helper.rb`, `app/views/dashboard/show.html.erb` | Candidate select, displayed score, per-row rescue | Medium |
| `app/services/assessment_csv_export.rb` | Score cell from the reader | Medium |
| `lib/score_report.rb`, `lib/tasks/` | The report and its task | Medium |
| `test/` | 16 cases; update the TKT-4 stored-score and TKT-3 export score tests | High |
| `assessment-log/` | Solution draft, benchmarks, snapshot evidence, ticket, decisions, prompts | Medium |

No migration, no gem.

## Contract summary
None across services. Single-repo change; see `contract.md`.

## PR strategy
One PR, base `main`, branch `feat/TKT-8/score-reader`, title `TKT-8 | Task 2: score reader, shared by dashboard and export, plus score report`. Yaml in `pr-strategy.yaml`.

## Test matrix

| ID | Req | Case | Type | Bucket | PR |
|---|---|---|---|---|---|
| UT-1 | 15 | Contract table: each seed shape maps to the agreed score or to nothing | positive | unit | 1 |
| UT-2 | 15 | Key order and first valid; later key used when earlier invalid; never combined | positive | unit | 1 |
| UT-3 | 15 | Strings: trim, percent sign, space before it, decimal comma; N/A, empty, text, comma plus three digits invalid | positive | unit | 1 |
| UT-4 | 15 | Range and proportion: 0, 1, 100 valid; below 0, above 100, strictly between 0 and 1 invalid with reasons | edge | unit | 1 |
| UT-5 | 15 | Round half up: 84.5, 84.4999, 84.99999, `"84,5"` | edge | unit | 1 |
| UT-6 | 16 | Never raises: nil, arrays, objects, booleans, huge numbers, non-object roots | edge | unit | 1 |
| UT-7 | 19 | Outcome names key, rules and reason | positive | unit | 1 |
| UT-8 | 20 | Each rule is a separate unit; a reader without one rule changes only what it did | positive | unit | 1 |
| UT-9 | 16 | Dashboard: Score not available for invalid or missing, normalised value otherwise; status does not matter | positive | unit | 1 |
| UT-10 | 28 | Export score equals the dashboard's for every shape; unavailable is blank | positive | unit | 1 |
| UT-11 | 16 | A raising reader is rescued: 200, that row Score not available, log has only class and id | negative | unit | 1 |
| UT-12 | 17 | `responses_json` unchanged after dashboard, export and report | positive | unit | 1 |
| UT-13 | 19 | Report: per-case counts, at most 5 scrubbed examples, per-rule counts, no emails, read-only | positive | unit | 1 |
| UT-14 | 14 | Dashboard log has no emails, response content or raw scores | positive | unit | 1 |
| UT-15 | 14, 28 | Neither dashboard nor export queries the whole `responses_json` | positive | unit | 1 |
| UT-16 | 15 | The candidate SQL is generated from the single list of keys | edge | unit | 1 |
| MC-1 | 19 | Report on the 500k seed; counts match the experiment | positive | manual | 1 |
| MC-2 | 27 | Snapshots: only the score column differs, only on expected rows | positive | manual | 1 |
| MC-3 | 26 | Benchmark and 200,000-row export time after the change | positive | manual | 1 |
| MC-4 | 16 | Browser check of the Score column | positive | manual | 1 |
| MC-5 | 26 | Bullet silent; `ab` repeated | positive | manual | 1 |

## Risks and mitigations
- **19% of the seeded rows show "Score not available".** That is the seed's deliberate mess (10.6% have no score at all), not a prediction; the report exists so the same numbers can be produced on a masked production copy before trusting the rules. A user who sees "Score not available" is never shown a guess (D-016).
- **The ambiguous-comma rule and the space before `%` are guesses** about legacy data, absent from the seed; both are single removable rules (Req 20) and the report counts their hits.
- **Printing tokens could leak free text.** Never raw: see Open question 4.
- **The reader runs in Ruby for every exported row** (about 0.35 s per 200,000 rows measured); the export total is re-measured (MC-3).
- **The snapshot's score column will differ.** Req 27 allows it; the evidence must show that nothing else changed (MC-2).
- **Float rounding surprises.** Half up is applied to the decimal value; the 84.99999 and 84.5 cases are tested.
- **Invariant writers:** none; nothing is stored.

## Open questions (need your decision)
1. **Confirm the contract against the evidence.** On the seed, 81.0% of rows show a score and 19.0% show "Score not available" (no score key 10.6%; a proportion such as 0.85 rejected 3.2%; non-numeric text 3.2%; out of range 2.1%). 6.4% come from an alias key, 8.5% are rounded, 5.3% are numbers stored as strings. Do you accept the contract as written, including rejecting proportions rather than scaling them (your earlier decision, T2-5)?
2. **Two details the spec did not define.** A comma followed by exactly three digits (`1,234`) is treated as ambiguous and invalid, while one or two digits (`84,5`) is a decimal comma; and a space before the `%` (`85 %`) is allowed. Neither occurs in the seed. Accept? (If yes, Req 15 is amended to say so.)
3. **Where the candidates are read.** Read the four candidate keys in SQL (3.2 times faster for 200,000 rows, free text stays in the database, the dashboard stops loading the large column) rather than loading the whole JSON in Ruby. I recommend SQL. Accept?
4. **Report tokens and privacy.** A token could be free text typed into the score key. I propose printing a token only when it is short and number-like (up to 20 characters of digits, letters, dot, comma, percent, space or hyphen, passed through the PII scrubber, so `N/A` and `85%` show), and otherwise printing `[text, 37 characters]`. Accept? (If yes, Req 19 is amended.)
5. **Draft SOLUTION.md section** lives in `assessment-log/solution-drafts/score-reader.md` now and is merged into SOLUTION.md by TKT-12. Accept?

## Out of scope
Rewriting stored data, gating the score on status, alerts or an error log for missing scores (Req 39), other key names, scales such as 1 to 5 or 0 to 10, anything about speed (done in TKT-5 to TKT-7).

## Estimated scope
About 12 files and 700 lines including tests. Single PR.

## Critic pass
Not run as a separate agent: single repo, no contract items.

## Self-check
- Reqs 14 to 20 and 28 all land in PR 1 with unit cases; the measurements are manual rows MC-1 to MC-5.
- Spec amendments proposed after approval: Req 15 (the ambiguous-comma and space-before-percent definitions, first valid, booleans and non-scalars invalid, 0 and 1 valid) and Req 19 (how report tokens are shown).

## Implementation notes (added after building)
- Built as planned; the open-question recommendations were accepted (candidates read in SQL, first valid key wins, 0 and 1 valid, proportions strictly between 0 and 1 rejected).
- Brakeman flagged interpolated SQL in the model, so the alias SQL is generated in `ScoreReader.candidate_select_sql`.
- The report tightened token printing during testing (short free-text words could be names): only digits/number punctuation or placeholder words are printed, otherwise `[text, N characters]` (Req 19 amended).
- Measurements: MC-1 report (`benchmarks/score-report-500k-seed.txt`), MC-2 snapshots (score column only), MC-3 benchmark and export (export 3,767 to 2,552 ms median), MC-5 Bullet log empty and `ab` repeated. MC-4 (browser check) was covered through the full-stack integration session used by `dashboard:snapshot`, which renders the real page; not clicked in a browser.
