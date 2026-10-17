# 0026 — Wide player-season stat table in the DuckDB bundle

- **Status:** Accepted
- **Date:** 2026-10-17

## Context

The DuckDB bundle (`data/cfbstats.duckdb`, decision 0016) carries the cleaned
tables, but the only stat table is `player_stats`, which is **long** — one row
per player-season-category-statType-stat (~1.5M rows). Every SQL question that
touches statistics must pivot ~54 `(category, statType)` pairs with a
`TRY_CAST(stat AS DOUBLE)` first; the long table's string-typed `stat` column
makes naive aggregation silently wrong and adds friction to every query. An
assessment of the bundle against `inst/dict` also surfaced that the
drafted-rate-by-tier example query in `inst/data-model.md` counted **stat
lines**, not players (it did not aggregate to player-season grain before
joining).

## Decision

1. Add `build_player_season_stats(player_stats)` (in `R/duckdb.R`): pivot the
   long stats to one row per `(playerId, season, team)` with one numeric column
   per `(category, statType)` pair, named `<category>_<statType>` (lowercased,
   non-alphanumerics to `_`). Duplicate pairs are summed; pairs a player-season
   never logged are `NA`. The category must appear in the column name because
   `statType` repeats across categories (`TD` exists in passing AND rushing).
2. Materialize it into the DuckDB bundle via the `duckdb_file` target, as a
   **derived** table like `ps_change`/`roster_flags`/`career_summary`
   (decision 0021): documented in `inst/dict/player_season_stats.yml`, not
   published as standalone parquet, so track-mode builds need no new release
   asset.
3. Guard it with `contract_player_season_stats()` (key grain 1:1, non-null
   keys, season window, finite stat columns) wired into the `contract_gate`.
   Non-negativity is deliberately NOT asserted: real data carries negative
   values (sack-adjusted rushing yards, return averages on negative plays).
4. Fix the grain error in the drafted-rate-by-tier example query in
   `inst/data-model.md` (aggregate to player-season grain first) and add a
   wide-table example.

Alternatives considered: doing the pivot inside `build_duckdb()` with a SQL
`PIVOT` (less testable, harder to document column-by-column); naming columns
with the taxonomy `label` (verbose, less predictable); publishing the wide
table as parquet (unnecessary — it rebuilds from the cleaned long table in any
mode).

## Hypotheses / expectations

- SQL users can answer stat questions (e.g. per-season passing yardage)
  without touching the long table, cutting a whole class of casting/pivoting
  errors.
- The bundle stays self-describing: the new table's dict is checked against
  the function output schema by `test-dict-derived.R` (identity columns exact;
  stat columns match the documented naming pattern).

## Consequences

- The bundle grows by one ~5 MB table; `build_player_season_stats` runs in the
  pipeline, so the contract gate now also covers the pivot.
- Any new `(category, statType)` pair arriving in `player_stats` adds a column
  automatically (the dict documents the pattern, not a fixed list) — the stat
  taxonomy coverage contract (decision 0019) still labels it.
- Column names are lowercased snake_case, which is a departure from the raw
  feed's uppercase `statType` tokens (`COMPLETIONS` → `passing_completions`).

## Outcome / what we learned

_Filled in later._
