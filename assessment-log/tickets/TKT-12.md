---
key: TKT-12
type: Task
title: Docs: README, final SOLUTION.md, benchmarks, demo outline
status: In Review
parent: EPIC-1
updated: 2026-11-07T08:28:15Z
---

## Description
**Context:** The deliverables are a README to run locally, a SOLUTION.md with design and trade-offs, and a demo video.

**Scope:** README (setup including `PGPORT`, seeding, running the job worker, signing in, running tests); final SOLUTION.md assembled from the sections added by earlier tickets, with the benchmark before and after tables, the async justification, the score assumptions, the Task 3 plan and a Future work section; a demo walkthrough outline covering architecture, key decisions, trade-offs and interesting implementations; the PROMPTS.md summary at the top.

**Not in scope:** Recording the video (done by the author).

**Depends on:** TKT-8, TKT-11

**Spec requirements:** Req 35, Req 18, Req 26, Req 39 (see `assessment-log/spec/spec.md`)

**Notes and risks:**
- Prompts stay verbatim with a summary at the top, as agreed.

## Acceptance criteria
- Req 35: A fresh clone follows the README to a running app, including setting PGPORT (database.yml defaults to 5433), seeding and running the job worker; SOLUTION.md covers design, trade-offs, the async choice, the score assumptions, benchmarks and the Task 3 plan; a demo walkthrough outline exists for the author's own use and is deliberately not committed (user, 2026-11-07).
- Req 18: The score reader file begins with a comment block stating the key order, parsing rules, range rule and limitations; SOLUTION.md has a section stating plainly that the data shape is unknown, listing each assumption and the known legacy issues covered, noting that displayed scores can differ from stored data, and naming a masked production copy as the ideal validation.
- Req 26: Baseline, pagination, eager loading, index and the score reader are separate changes, each revertible alone; each records before and after numbers (time and query count); SOLUTION.md has the before/after note and why each step was chosen; no claim in the docs lacks a number.
- Req 39: SOLUTION.md has a Future work section naming these; none is implemented.

## Definition of done
- PR links this ticket (`TKT-12` in the title) and updates `assessment-log/` (prompts, decisions) in the same PR.
- CI passes locally where possible: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rails db:test:prepare test`, `yarn typecheck` when TypeScript changes. Anything not runnable locally is said so in the PR.
- No commit, push or PR without the author's explicit permission.

## Comments
- 2026-11-07 implementation: README (fresh-clone run verified in a scratch clone against a throwaway database), SOLUTION.md assembled from the decisions, benchmarks and the two drafts (drafts removed), docs tests (`test/docs`), PROMPTS.md summary refreshed, merged tickets marked Done. The demo outline was written for the author's own use and, by the author's decision, is not committed. Spec Req 35 amended to say so.

