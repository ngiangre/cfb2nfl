---
name: cfb2nfl
description: >-
  Work with the cfb2nfl college-football data and analysis in this repository.
  Use when loading, cleaning, joining, or modeling the CFBD draft-picks,
  player-season-stats, roster, or coaches datasets, building features toward
  predicting NFL draft outcomes, or extending the targets pipeline / Quarto
  site. Covers the data schemas, known linkage gotchas, and project conventions.
---

# cfb2nfl

Analysis of what predicts (and explains) a college football player being drafted
into the NFL — both explanatory (inference) and predictive answers.

The canonical guidance lives in the repo, not here:

- **[AGENTS.md](../../../AGENTS.md)** — project memory: the data tables and their
  grain/keys, the *critical gotchas* (athlete-id player key, long stats, silent
  join loss, head-coaches-only, static roster weight, season-aware tiers, the
  gitignored-parquet / `data-latest` release flow), how we work
  (population/outcome, out-of-time evaluation, contracts + TDD), the `targets`
  pipeline and audit layer, conventions/stack, and the git workflow.
- **[VISION.md](../../../VISION.md)** — the why: questions, scope, philosophy.
- **`inst/dict/*.yml`** — per-column data dictionaries (types, provenance) for
  every table; the source of truth for schema detail.
- **`decisions/`** — ADR log for substantive choices.

Read AGENTS.md before substantive work; follow its conventions and gotchas.

## One practical note

`player_stats` is large and **long** — read it lazily, filter/pivot, then
collect, rather than pulling the whole table into memory:

```r
library(arrow)
library(dplyr)

read_parquet("data/player_stats.parquet", as_data_frame = FALSE) |>
  filter(...) |>
  collect()
```
