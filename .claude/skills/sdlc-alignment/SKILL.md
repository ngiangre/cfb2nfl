---
name: sdlc-alignment
description: >-
  Use when starting, scoping, planning or finishing any cfb2nfl work that
  changes what the site offers: a new idea or question, a GitHub issue, a
  plans/*.md plan, a new post, explorer tab, data source or model, a branch
  or PR, or when asked "does this fit the goals?", "what should we build
  next?", or "where does this stand?". Also use when the user's request seems
  to drift from the site's purpose or audience.
---

# sdlc-alignment

Every piece of work traces **issue → feature → goal → persona**, and two
read-only reviewer agents check each link. The registry lives in
[`product/`](../../../product/README.md): `personas.md`, `goals.md`,
`features.md`. Read all three before scoping anything.

**Core rule:** no issue without a feature, no feature without a goal or
constraint. If work fits none, say so to the user before building it; adding
a goal is their call (with a decision record), not yours.

**Priority:** G1, G3, G4, then G2. Constraints C1 (trust) and C2 (API
budget) bind every feature. When asked what to build next, prefer the
highest-priority goal with an `accepted` or `idea` feature.

## The flow

| Stage | You do | Gate |
|-------|--------|------|
| 1. Intake | Restate the request as a persona need ("P1 wants to know ..."). Find its feature in `features.md`. | none |
| 2. Feature | Existing feature: reuse its ID. New capability: add a card (`idea`) under its primary goal, from the template below, and bump "Next free ID". | run **`feature-reviewer`**; status → `accepted` only on "aligned" |
| 3. Tasks | Open one GitHub issue per task (template below): `Feature: Fnn` in the body, the card's goal labels, the criteria it covers. Then run `sync_feature_tasks()`. | run **`task-reviewer`** on the feature's issues (or the plan) before building |
| 4. Build | Normal repo workflow (TDD, contracts, `architecture-improver`, `vignette-reviewer` for figure cards). Status → `in progress`. | none |
| 5. Finish | Before the PR: run **`task-reviewer`** on the branch diff. PR body says `Feature: Fnn` and `Closes #NN`; the NEWS entry names the feature. After merge, `sync_feature_tasks()`, tick the met criteria, status → `shipped` when all are met. | reviewer verdict "delivers" |

Small fixes (typos, a broken link, a CI repair) skip stages 2–3: put
`Feature: Fnn` in the PR body and move on.

Invoke a reviewer with the Agent tool (`subagent_type: feature-reviewer` or
`task-reviewer`), passing the feature ID and the issue numbers, plan path or
branch. Report its verdict and act on the findings before the next stage; if
you disagree with a finding, tell the user why rather than skipping it.
GitHub calls use the `gh` R package (AGENTS.md "Git"); creating issues and
labels is outward-facing, so confirm with the user first unless they asked
for it.

## Feature card template

Under the card's primary goal heading in `product/features.md`:

```markdown
### F23 · <capability, stated from the persona's side>

- **Goals:** G3, C2 · **Personas:** P1 · **Status:** idea
- **Why:** <the question, follow-up or gap that motivates it>
- **Acceptance criteria:**
  - [ ] <observable outcome a persona or a check can confirm>
- **Out of scope:** <what this feature deliberately does not do>
- **Cost:** <CFBD calls, new tables, decision records needed>
- **Review:** feature-reviewer YYYY-MM-DD: aligned
- **Tasks:**
<!-- tasks F23 -->
<!-- /tasks -->
```

The Goals line drives the labels: `G1`–`G4` → `goal:G1`–`goal:G4`, `C1` →
`constraint:trust`, `C2` → `constraint:budget`. Criteria are outcomes ("a
fan can filter the funnel to their school"), not activities ("write the
filter"). Repo gates that apply to every feature (contracts, NEWS,
publish-before-merge, post review) are checked by the task reviewer and need
not be restated.

## Issue template

```markdown
<what and why, from the persona's side>

Feature: F23 (criteria 1, 3)

- [ ] <done-when items>
```

Labels: every goal/constraint on the feature's Goals line.

## Red flags: stop and check alignment

- "While I'm here I'll also add ..." (scope creep: a new issue, maybe a new
  feature)
- An issue with no `Feature:` line, or one that closes no criterion
- A feature whose only persona is "us" or "the pipeline" (name the persona
  it ultimately serves, or the constraint it protects)
- Starting G2 work while a G1/G3/G4 feature the user accepted is waiting,
  without saying so
- Marking a feature `shipped` with unticked criteria
- Editing `goals.md` to make a feature fit
- Hand-editing inside `<!-- tasks -->` markers (run the sync instead)

## Status questions

"Where does this stand?" Run `sync_feature_tasks()`, then answer from
`features.md` grouped by goal in priority order: each feature's status,
ticked criteria and open issues. Flag goals with no `accepted` or
`in progress` feature, and post `followups:` with no feature.
