# Product: goals, features, tasks

Keeps the site aligned with what it is for as it grows. Three levels, each
traced to the one above it:

```
personas.md   who the site serves (P1 invested fan, P2 coder & researcher)
   │
goals.md      what the site is for, in priority order G1, G3, G4, G2,
   │          plus constraints C1 (trust) and C2 (API budget)
   │  reviewed by the feature-reviewer agent
features.md   capabilities (Fnn) grouped by goal, each card with acceptance
   │          criteria and a generated task checklist
   │  reviewed by the task-reviewer agent
GitHub issues each task: a "Feature: Fnn" line in the body or a comment,
              and a label per goal/constraint (goal:G1, constraint:trust, ...)
```

- Filter issues by goal on GitHub with the labels
  (`label:goal:G3`); see a feature's tasks on its card in `features.md`.
- Refresh the cards' checklists after opening or closing issues:
  `Rscript -e 'pkgload::load_all(quiet = TRUE); sync_feature_tasks()'`
  (`R/feature_tasks.R`). It also warns about issues missing their feature's
  goal labels.
- [VISION.md](../VISION.md) is the why; `goals.md` restates it as outcomes
  with signals. Changing a goal needs a decision record.
- `decisions/` records ratified choices; `plans/` holds multi-session work
  plans (a plan delivers one feature and says so at the top).
- The workflow, the card template and when each reviewer runs live in the
  `sdlc-alignment` skill (`.claude/skills/sdlc-alignment/`). Applying the
  personas lives in the `site-personas` skill.
- The reviewers are `.claude/agents/feature-reviewer.md` (feature → goals)
  and `.claude/agents/task-reviewer.md` (tasks → feature). Both are read-only.
