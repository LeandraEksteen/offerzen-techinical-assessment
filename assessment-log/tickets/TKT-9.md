---
key: TKT-9
type: Task
title: Task 3: assessor status screen, free-text baseline
status: To Do
parent: EPIC-1
updated: 2026-11-07T08:28:15Z
---

## Description
**Context:** Assessors currently type any status they like. To show the before and after, the baseline screen keeps the legacy free-text behaviour.

**Scope:** One form to edit an assessment's status as free text for signed-in admins of its company (existing sign-in, no new role).

**Not in scope:** Validation, the dropdown, default status, the cut-over switch (TKT-10).

**Depends on:** TKT-1

**Spec requirements:** Req 41 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- Req 41 is delivered in two steps: the free-text baseline here and the dropdown in TKT-10. Acceptance for this step: a signed-in admin can save any text as the status of an assessment of their company; admins of other companies cannot.

## Acceptance criteria
- Req 41: One form edits an assessment's status for signed-in admins of its company (existing sign-in, no new role); the baseline version offers a free-text field; the later version offers a dropdown of the five values that cannot be saved empty, with server-side validation from Req 29; both versions are visible in git history.

## Definition of done
- PR links this ticket (`TKT-9` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
