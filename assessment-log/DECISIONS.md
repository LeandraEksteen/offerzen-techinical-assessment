# Decisions

Format: ID, decision, context, rationale. Newest at the bottom.

## D-001: Keep the log in `assessment-log/` inside the repo
- **Context:** Prompts, decisions and tickets need a home. No Jira for this exercise.
- **Decision:** One folder at the repo root holding `PROMPTS.md`, `DECISIONS.md` and `tickets/`.
- **Rationale:** Reviewers can read it or ignore it. It travels with the code.

## D-002: Prompts logged verbatim, with a summary at the top at the end
- **Decision:** `PROMPTS.md` holds prompts as typed. A summary is added at the top once the work is complete.

## D-003: Tickets are markdown files in `assessment-log/tickets/`
- **Decision:** One epic plus one groomed ticket per task. Every PR references its ticket ID.

## D-004: Git workflow
- **Decision:** Branch from `main`, one branch and one PR per ticket. Log and ticket updates ship in the same PR as the work they describe.
- **Rationale:** Keeps each PR self-explanatory and reviewable on its own.
- **Note:** The scaffold branch was already merged to `main` (PR #1).

## D-005: No commits, pushes or PRs without explicit permission
- **Decision:** The assistant asks before every commit, push and PR, and asks rather than assumes when requirements are unclear.

## D-006: The 4-hour timebox in the brief is ignored
- **Decision:** Per the author, scope is driven by the requirements, not the clock. The brief's call for restraint and targeted changes still applies.

## D-007: Task 1 export is asynchronous (background job + history table)
- **Context:** The brief allows streaming or async. The company has ten years of data and the dashboard is already slow.
- **Decision:** User picks filters and clicks download. A job builds the CSV in batches. The download page shows a history table with status (in progress, then ready). V1 has no polling or global banner: the page asks the user to refresh in a few minutes.
- **Rationale:** A long request would hold a web worker and risk freezing the UI. Polling and a global "ready" banner are noted as a later improvement.

## D-008: A PII scrubbing service covers exports and logs
- **Decision:** One shared service scrubs PII from any model, for export output and for logs and error logs.

## D-009: Export date filter uses `assessment_date`, not `created_at`
- **Rationale:** An assessment can be scheduled but not yet completed, so creation time is the wrong axis.

## D-010: Admin login is a plain table-backed form
- **Decision:** Email and password against a local table. No third-party login.

## D-011: No insecure legacy export is built
- **Decision:** Only the secure export is built. SOLUTION.md describes the legacy behaviour from the brief and how each risk is addressed.

## D-012: Task 1 status dropdown lists the distinct stored status values
- **Context:** Task 1 is built without knowing Tasks 2 and 3 are coming. There is no write-side enforcement yet, so a maintained alias list is not feasible.
- **Decision:** The dropdown shows the unique statuses found in the company's data, including non-standard ones. After Task 3 standardises writes and backfills history, the same query collapses to the canonical set.
- **Trade-off:** Users see messy options until then. This is the motivation for Task 3.

## D-013: Score contract for `responses_json`
- **Context:** The brief never says where the score lives or its scale. We are effectively blind and are covering legacy problems the author has met before.
- **Decision:** Take the first valid value from top-level keys `score`, `assessment_score`, `total_score`, `overall_score`, in that order, with no combining. Accept numbers and numeric strings (trailing `%` stripped, one decimal comma read as a point). Valid range is 0 to 100. A value strictly between 0 and 1 is treated as ambiguous and is not scaled (changed from scaling it after T2-5, because a user shown a guessed value must not doubt it). Round half up. Anything else displays "Score not available" and is counted by reason in a log line that holds no PII or values. One model method serves both dashboard and export.
- **Known limitation:** Scales such as 1 to 5 or 0 to 10 cannot be told apart from low percentages.
- **Documentation requirement:** The contract is summarised in code comments for the next developer, and the assumptions are stated plainly in SOLUTION.md.
- **Ideal validation:** Run the transformation against a masked production copy and review the outcomes.

## D-014: Score normalisation is read-time only
- **Decision:** Stored `responses_json` is never rewritten. What the admin sees can therefore differ from what is in the database. The author called this out as important, so it is documented in code comments and in SOLUTION.md.
- **Related:** A read-only dry-run report (proof of concept) prints outcome counts and a few examples per normalisation case, so the author can eyeball accuracy on seeded data now and on a masked production copy later.

## D-015: Status does not gate the score display
- **Rationale:** Statuses are still dirty, so gating on them would hide valid scores.
- **Future work:** After statuses are normalised, consider gating, an alert, or an error log for scores that are missing on completed assessments.

## D-016: No "scores may differ" footnote on the dashboard
- **Decision:** The user must be sure of a displayed score and not doubt it. The normalisation call-out lives in code comments, SOLUTION.md and the dry-run report instead.

## D-017: Performance work is benchmarked and shipped one change at a time
- **Decision:** Baseline first on a 500k-row seed, measured locally (Bullet, rack-mini-profiler, EXPLAIN ANALYZE, a simple load test). Then pagination, eager loading and one composite index on (company_id, assessment_date) built concurrently, each as its own PR with before and after numbers. Staging, production and APM measurement are described in SOLUTION.md only.
- **Rationale:** No "it feels faster". A plain status index would not be used because the status filter is trimmed and case-insensitive.

## D-018: Task 3 approach
- **Decision:** Stop bad data first. The assessor front end changes from free text to a five-value dropdown, announced by a change request with a cut-over date. In Ruby, non-canonical values are rejected only when status is set, with no alias mapping on write. Before the cut-over date the app only logs a count of would-be rejections, with no values.
- **No database constraint:** The author does not consider it the database's job.
- **Backfill (plan only):** Build a Google sheet of distinct status values with counts and latest `updated_at`, map them to the five values with assessors confirming doubtful ones, and keep the approved mapping as a versioned file. Add a nullable column, write both columns, backfill in batches, and verify 100% before switching. Switch with an alias, keep the legacy column written, then rename in a short low-traffic window with maintenance mode and a backup taken right before. Drop `legacy_status` later.
- **Rationale:** Rollback is a deploy or a reverse rename, not a full restore, and rows written meanwhile stay safe. The rename avoids permanent tech debt and other readers of the column keep working.
- **Defaults and safeguards:** A new assessment without a status defaults to `pending`. The large-table safeguards are agreed, with pause thresholds of replication lag over 5 seconds, any lock wait over 2 seconds, or request latency over 1.5 times baseline.

## D-019: Scaffold choices (TKT-1)
- **Employee email:** `employees` has its own `email` in addition to the brief's denormalised `assessments.employee_email`. Task 2's baseline needs a page that reads the employee record to show the N+1.
- **No indexes on assessments:** the table is created with only a primary key (foreign keys without indexes) so the Task 2 baseline reflects a legacy table. The composite index arrives in its own ticket.
- **bcrypt:** enabled for `has_secure_password`, with rate limiting on sign-in.
- **Seed layout:** `db/seeds.rb` stays small because `bin/ci` runs `db:seed:replant` in the test environment. The 500,000-row dataset is a separate task, `assessments:seed`, deterministic and refusing to run in production. It silences SQL logging so no emails or responses reach the log.
- **Dev sign-in:** seeded admins use a documented development password from `SEED_ADMIN_PASSWORD` (default in the seeder), never used outside seeding.

## D-020: PII scrubbing design (TKT-2)
- **One declaration per model:** `pii_attributes` registers names for the scrubber, the global request parameter filter and `inspect` redaction. Declared: Assessment (`employee_email`, `responses_json`), Employee (`name`, `email`), Admin (`email`, `password_digest`). A company name is not treated as personal.
- **Formatter as backstop:** every log line, including error logs, is scrubbed after formatting (emails and declared attribute values in hash, JSON, key-colon, SQL equals and bind-array shapes). It fails closed. Production builds its own logger, so the formatter is passed to it explicitly.
- **Primary protection is not logging data:** job arguments are ids or records only and are not logged; bulk SQL is not logged (the seeder silences it).
- **Known limits:** positional values in bulk `INSERT` SQL cannot be matched by attribute name (only emails are caught); `as_json`, `pluck` and rendered HTML are not scrubbed; the global parameter filter also hides any parameter called `name`; the development error page can show values.

