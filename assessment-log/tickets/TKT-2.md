---
key: TKT-2
type: Task
title: PII scrubber service and log hygiene base
status: To Do
parent: EPIC-1
updated: 2026-11-07T08:28:15Z
---

## Description
**Context:** One shared service keeps personal data out of exports, logs and error logs. Both Task 1 and Task 2 use it, so it is built first.

**Scope:** A scrubber service; a per-model declaration of PII attributes (for example `employee_email`, `responses_json`) that drives the Rails parameter filter, `inspect` output and a log and error-log formatter; a test helper that captures logs and checks for leaked values.

**Not in scope:** The export itself and the dashboard (they consume the scrubber in later tickets). Req 13's export and dashboard flow checks are completed in TKT-3 and TKT-8.

**Depends on:** TKT-1

**Spec requirements:** Req 12, Req 13 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- Background-job arguments must carry ids only; the scrubber test should show it.
- Keep it small: one declaration per model, no per-feature configuration.

## Acceptance criteria
- Req 12: Each model declares its PII attributes once (for example employee_email, responses_json); that declaration drives the Rails parameter filter, inspect output and a formatter that redacts those values in logs and error logs; export rows pass through it as a second guard; background-job arguments carry ids only.
- Req 13: After a scripted run of an export (including a failing one) and dashboard loads with filters, the captured log and error output contains no employee email, response content or raw score value (checked by a test that greps the captured log).

## Definition of done
- PR links this ticket (`TKT-2` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
