---
key: EPIC-1
type: Epic
title: Safely extend the legacy Assessments module
status: To Do
parent: null
updated: 2026-11-07T08:28:15Z
---

## Description
Take over a ten-year-old Rails app that manages employee ergonomic and health assessments for companies. Add a company-scoped CSV export, make the dashboard faster and its score trustworthy, and standardise status values with a safe release plan, without rewrites. The data is health related and the assessments table is large, so tenant isolation, privacy and not stalling the app drive every choice.

Source of truth: `assessment-log/spec/spec.md` (approved) and `requirements.yaml` (45 requirements). Decisions: `assessment-log/DECISIONS.md`. Prompts: `assessment-log/PROMPTS.md`.

**Out of scope for the epic:** database check constraint (Req 30), emailing the CSV (Req 37), an insecure legacy export (Req 38), polling, a global done-banner, score gating or alerts, staging or production measurement (Req 39), executing the historical backfill.

**Order:** follows the brief (Task 1, Task 2, Task 3) after the scaffold and the PII scrubber. Each ticket is one branch from `main` and one PR.

## Acceptance criteria
- Every active requirement in the spec is delivered by a ticket below.
- README, SOLUTION.md and a demo outline are delivered (TKT-12).

## Comments

## Children
- TKT-1: Scaffold: data model, admin sign-in, large messy seed data
- TKT-2: PII scrubber service and log hygiene base
- TKT-3: Task 1: async company-scoped CSV export with history table and minimal TypeScript UI
- TKT-4: Task 2: baseline dashboard and benchmark method
- TKT-5: Task 2: dashboard pagination
- TKT-6: Task 2: eager loading on the dashboard
- TKT-7: Task 2: composite index for the dashboard and export date filter
- TKT-8: Task 2: score reader, shared by dashboard and export, plus score report
- TKT-9: Task 3: assessor status screen, free-text baseline
- TKT-10: Task 3: status validation, default, cut-over date switch, dropdown
- TKT-11: Task 3: status report and the backfill, release and rollback plan
- TKT-12: Docs: README, final SOLUTION.md, benchmarks, demo outline
