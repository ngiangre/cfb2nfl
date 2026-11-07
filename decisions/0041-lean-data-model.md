# 0041 — Keep the data model lean: derived tables start in the investigation

- **Status:** Accepted
- **Date:** 2026-11-07

## Context

Decision 0021 made every derived table a first-class member of the data model:
a pipeline target, a pointblank contract, an audit row, an `inst/dict`
dictionary, a DuckDB table and a row in `inst/data-model.md`. Each new
investigation then added its own derived table (0026, 0035, 0037, 0038, 0039),
and the model grew to 29 tables, 16 of them derived. The model was
comprehensive but hard to take in, and many of the derived tables served a
single post.

A survey of the derived tables showed:

- Read by no post: `career_end`, `player_season_stats` (its only consumer was
  the querychat app, which may be revised or removed and was not considered).
- Read by exactly one post, and feeding no other table: `roster_flags`
  (expectation checks, plus the visualizations page and `player_dossier()`),
  `season_arc` and `game_production` (performance arcs), `player_usage`
  (playing time), `position_path` (position stability).
- Read by no post from the DuckDB, but an input to other derived targets:
  `nfl_pick_link` (`picks_nfl`, the name-guarded draft-slot bridge, which feeds
  `outcomes` and `position_path`).

Most of the single-post tables are a short query over the cleaned tables; two
(`position_path`, `player_usage`) carry real join logic that their contracts
guard.

## Decision

A derived table enters the data model once a **second** investigation needs it,
or once another table is built from it. Until then it is built where it is
used, at one of two levels:

1. **On the fly in the post.** Keep the exported `build_*()` function and its
   testthat tests in `R/`; drop the target, contract call, audit row,
   dictionary, DuckDB table and data-model entry. The post calls the function
   on the tables it already loads. Applied to `roster_flags`
   (`flag_redshirt()`), `career_end` (`career_end_status()`), `season_arc`
   (`build_season_arcs()`), `game_production` (`build_game_production()`) and
   `player_season_stats` (`build_player_season_stats()`). The contract
   functions remain exported for a post that wants to run them.
2. **Pipeline step only.** For complex logic that a data contract should guard
   on every build, keep the target and its contract (and audit row), read it
   with `targets::tar_read()`, but keep it out of the DuckDB, `inst/dict` and
   `data-model.md`. Applied to `picks_nfl`, `position_path` and
   `player_usage`.

The `player_season_inputs` view (`ps_change` minus the label columns) is
dropped with it: it protected ad hoc SQL users of the app, and no post uses it.

The documented model drops from 29 tables to 21: 13 cleaned source tables,
`stat_taxonomy`, six derived tables (`ps_change`, `career_summary`,
`player_game`, `team_season`, `team_draft`, `outcomes`) and `audit_log`.

Alternatives not taken: keeping everything bundled (the status quo, which is
what made the model hard to read), and dropping the contracts for the complex
single-post tables too (it would let a silent join loss reach a post).

## Hypotheses / expectations

- A reader can hold the data model in their head: every bundled table is
  either a source table or a building block used in more than one place.
- Posts are unchanged in output: the on-the-fly builders are the same
  functions the targets called, so the rendered numbers do not move.
- The promotion rule makes the cost of a new table proportional to its reuse.

## Consequences

- Posts that build a table on the fly re-run the builder when they re-render;
  `freeze: auto` limits that to edits of the post itself.
- Removed dictionaries live in git history and are restored on promotion
  (`git show <sha>:inst/dict/<table>.yml`).
- The DuckDB file no longer carries `nfl_pick_link`; SQL users get the
  name-guarded `gsis_id` from `outcomes` instead.
- The querychat app's prompts still mention `nfl_pick_link` and
  `player_season_stats`; they need revising if the app is kept.
- Amends 0021 (which derived tables are bundled) and 0026 (the wide stats,
  bridge and view in the bundle).

## Outcome / what we learned

_Filled in later._
