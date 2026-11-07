---
key: TKT-4
type: Task
title: Task 2: baseline dashboard and benchmark method
status: To Do
parent: EPIC-1
updated: 2026-11-07T08:28:15Z
---

## Description
**Context:** Task 2 needs a real before. This ticket adds the legacy-style dashboard and fixes how it will be measured before anything is improved.

**Scope:** One company-scoped table (employee email, employee id, assessment date, status, score as currently stored) with date and status filters using the same semantics as the export; unpaginated with an N+1 on employees; Bullet and rack-mini-profiler in development; a documented measurement script or steps (query count, EXPLAIN ANALYZE, a simple load test with hey or k6) and the baseline numbers recorded on the 500k seed; a regression check that captures page 1 of the big company for later comparison.

**Not in scope:** Any improvement (TKT-5 to TKT-8). Staging, production and APM measurement are described in SOLUTION.md only (Req 39).

**Depends on:** TKT-1

**Spec requirements:** Req 21, Req 22, Req 27 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- Record real numbers, not impressions.
- The score shown here is the naive stored read; the contract reader arrives in TKT-8.
- Dashboard log hygiene is verified in TKT-8.

## Acceptance criteria
- Req 21: The page lists only the signed-in admin's company assessments with columns employee email, employee id, assessment date, status, score; its date and status filters use the same semantics as Req 5 and Req 6; it is visible only to signed-in admins.
- Req 22: A first change adds the unpaginated dashboard with an N+1 on employees; measurements on the 500k seed using Bullet, rack-mini-profiler, EXPLAIN ANALYZE and a simple load test (hey or k6) are recorded as numbers before any improvement; staging, production and APM measurement are described in SOLUTION.md only.
- Req 27: Before and after each change, page 1 of the seeded big company shows the same rows in the same order with the same values (apart from scores fixed by the score reader); the page returns 200 for every status and date filter combination in the seed.

## Definition of done
- PR links this ticket (`TKT-4` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
