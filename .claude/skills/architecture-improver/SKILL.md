---
name: architecture-improver
description: >-
  Keep the cfb2nfl architecture understandable and auditable, and catch loose
  ends before they ship. Use when adding or changing R functions, extending the
  targets pipeline, altering the data model or naming/style conventions, or
  building graphics/models. Verifies changes with behavior/test-driven
  development (testthat logic + pointblank data contracts) and checks that
  graphics and models preserve expected row counts and the intended data
  subsets. Actively makes the fixes and the accompanying tests/contracts.
---

# architecture-improver

Guard the *legibility* and *integrity* of the cfb2nfl architecture. Two jobs:
make the structure easy to understand and audit, and make sure no change leaves
loose ends — enforced by tests and data contracts, not by inspection alone. Read
[VISION.md](../../../VISION.md), [AGENTS.md](../../../AGENTS.md), and the relevant
`decisions/` records before substantive work.

## What "architecture" means here

- **Functions** in `R/` organized by pipeline stage: `ingest.R`, `clean.R`,
  `link.R`, `features.R`, `model.R`, `contracts.R`, `audit.R`, `viz.R`. Reusable
  logic with `roxygen2` docs.
- **The `targets` pipeline** (`_targets.R`) — the single source of truth for the
  DAG (decision 0004). Stages: ingest → clean → link → features → model → report.
- **The data model** — the athlete-id namespace, long stats, season-aware
  conference tiers, static roster weight (see AGENTS.md "Data" / "Gotchas").
- **Naming/style conventions** — see AGENTS.md "Conventions & stack".
- **The lineage/audit layer** — `audit_step()` → `audit_log`, data dictionaries
  in `inst/dict/*.yml` (decision 0005).

## Principles

1. **Behavior/test-driven.** Any behavior change is defined by a test *first* or
   alongside: `testthat` for function logic, `pointblank` for data. If you change
   behavior without a test that would have caught the old bug, you're not done.
2. **No silent row loss or schema drift.** Joins, pivots, filters, and collapses
   must have expected row-count/coverage assertions. AGENTS.md "Lineage"
   documents the known intentional deltas — new deltas must be *explained and
   asserted*, not discovered later.
3. **Graphics and models preserve counts and subsets.** Before a plot or model,
   assert the working frame is the intended population — draft-eligible seasons,
   the right denominator (players with a stat line), no accidental `NA`-drop or
   join fan-out. A chart that silently plots a filtered subset is a bug.
4. **Auditability.** Every data-touching step should emit an `audit_step()`
   record and keep its dictionary (`inst/dict/*.yml`) current, so any number on
   the site traces back to source.
5. **Legibility.** Names, stage placement, and roxygen should let a new reader
   follow the DAG without archaeology. Prefer clarifying structure over comments.

## Workflow

1. **Map before changing.** Locate the target(s) and function(s) involved and
   read them. Inspect the live graph rather than guessing:
   ```r
   targets::tar_manifest()   # every target, its command, and dependencies
   targets::tar_visnetwork() # DAG with up-to-date / outdated status
   targets::tar_outdated()   # what a change would invalidate
   ```
2. **Write/adjust the check first.** Add the `testthat` test or `pointblank`
   contract (in `contracts.R`, wired into the pipeline) that encodes the expected
   behavior/counts/subset. Confirm it fails for the right reason.
3. **Make the change**, smallest fix that satisfies the check. Keep functions on
   their correct stage; update roxygen and the data dictionary if the schema or
   contract changed.
4. **Verify end to end.**
   ```r
   devtools::load_all(); devtools::document(); devtools::test()
   targets::tar_make()   # or tar_make(names) for the affected subgraph
   devtools::check()     # conventions gate — keep it 0/0/0 (decision 0002)
   ```
   For a data/model change, let CI's `testthat` + `pointblank` pass before
   merging (AGENTS.md "Git").
5. **Check for loose ends.** After a change, sweep for what it *implies*:
   downstream targets now outdated (`tar_outdated()`), stale roxygen/`man/*.Rd`,
   an unpublished new table (must be `pb_upload`ed to the `data-latest` release
   before a fresh build can find it — AGENTS.md "Gotchas"), a contract that
   should tighten, a dictionary out of date, and a `NEWS.md` entry (decision
   0007). Report anything you can't safely resolve.

## Count/subset preservation — concrete checklist

Before graphics or modeling, assert (and, where natural, encode as a contract):

- Row count matches the expected population for this step; deltas from a prior
  step are explained.
- Join key coverage is what you expect; no unintended fan-out or drop.
- `NA` handling is deliberate — you know how many rows drop and why.
- The frame is scoped to **draft-eligible seasons** and the correct denominator
  when that's the intent.
- Group sizes (per position/season/team) are sane before per-group summaries or
  models; small cells are flagged, not silently plotted.

## Boundaries

- Match scope: fix the architecture at hand and its direct loose ends; don't
  opportunistically refactor unrelated code.
- Substantive architectural choices (a new stage, a data-model change, a
  convention shift) follow the repo's decision-record + NEWS workflow (AGENTS.md
  "Decision log" / "Git") before landing.
- Respect existing decisions; if a change would contradict one, raise it with
  the user rather than overriding it.
- On the Explore vignette / `R/viz.R`: you own chart *correctness* and
  count/subset preservation; the fan-facing framing and copy belong to
  `fan-experience-improver`. Coordinate; don't rewrite the narrative.
