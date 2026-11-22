# 0048 — Goal → feature → task traceability with reviewer agents

- **Status:** Accepted
- **Date:** 2026-11-22

## Context

Work has been driven by issues (#4–#91), `plans/*.md` and the follow-ups of
each post. VISION.md states the purpose and the audience, but nothing ties an
individual issue or branch back to it, so drift is caught only when the user
reviews a finished post or page. The audience (VISION §10) is described in
two sentences, and the fan persona was fleshed out only inside the
`fan-experience-improver` skill.

## Decision

Settled in an interview with the user on 2026-11-22.

- **Personas** (`product/personas.md`): P1 the invested fan, primary, who
  also stands for the question collaborator (VISION §11); P2 the coder and
  researcher. P1 wins ties. No anti-persona list: features are judged
  against the goals alone.
- **Goals** (`product/goals.md`), in priority order: G1 answer the project's
  questions, G3 fan question → answer → next question (querychat deferred),
  G4 follow players into the NFL (split out of G1), G2 forecast draft
  outcomes. Trust/reproducibility and the API budget are **constraints** C1
  and C2 that bind every feature, not goals features advance.
- **Features** (`product/features.md`): Fnn cards grouped under their
  primary goal, backfilled from shipped work, with acceptance criteria for
  anything past `idea`.
- **Tasks are GitHub issues.** Each carries a `Feature: Fnn` line (body or
  comment) and one label per goal or constraint on its feature
  (`goal:G1`–`goal:G4`, `constraint:trust`, `constraint:budget`).
  `sync_feature_tasks()` (`R/feature_tasks.R`) regenerates each card's task
  checklist from GitHub and flags label mismatches. Existing issues were
  backfilled with labels and a `Feature:` comment.
- **Reviewers:** read-only agents `feature-reviewer` (feature → goals and
  personas) and `task-reviewer` (issues or a branch diff → the feature's
  criteria). The `sdlc-alignment` skill holds the workflow and templates;
  `site-personas` applies the persona cards.
- Not chosen: a `feature:Fnn` label per feature (20+ labels to maintain),
  milestones per feature, or hand-ticked checklists.

## Hypotheses / expectations

- Every new issue names a feature, and every accepted feature names a goal
  or constraint and a persona.
- The reviewers catch scope creep and misaligned features before building,
  not after the user reads the result. (In the first trial run the task
  reviewer caught a ~1,000-call CFBD backfill hidden in a plan that claimed
  zero calls.)
- Goals with no active feature (G2 and G4 today) stay visible.

## Consequences

- Goals and constraints change only with a decision record. Features are
  cheap to add.
- Small fixes skip the feature card and reviews; the PR just names the
  feature it touches.
- The task checklists depend on the GitHub API (`gh` R package, in
  Suggests); they are regenerated on demand, not in CI.

## Outcome / what we learned

_Filled in later._
