# 0029 — Dynamic branching for the games-family ingest

- **Status:** Accepted
- **Date:** 2026-10-18

## Context

The `/games` family (`games`, `game_team_stats`, `game_player_stats`) was
ingested by single targets whose ingest functions looped over years × season
types × weeks inside one R call (~1,150 throttled API calls for the full
sweep). One failed call — CFBD 429/503s are common under sustained bursts —
aborted the whole target, and the next run re-pulled every week from scratch,
wasting quota and wall time.

## Decision

Move the mapping into the `_targets.R` pipeline with dynamic branching
(decision 0028's pacing budget unchanged):

- `games_grid` (season × seasonType) → `raw_games_chunk` branches, one
  `/games` call per branch, combined into the unchanged `raw_games` target
  via a plain `dplyr::bind_rows()` aggregate target (a static target consuming
  a pattern target receives the full branch value).
- `week_grid` derives the played (season, seasonType, week) triples from the
  ingested `raw_games`, so the stats ingests never re-pull `/games` for week
  discovery; `raw_game_{team,player}_stats_chunk` branches each make one
  `/games/{teams,players}` call and are combined into the original
  `raw_game_{team,player}_stats` targets.

Downstream (clean → parquet assets → contracts → audit → DuckDB) is untouched:
the combined tables keep the same grain and names. The full-table
`ingest_*()` functions remain as the programmatic API; the new
`ingest_games_chunk()` / `ingest_game_{team,player}_stats_chunk()` helpers are
internal. The full-table functions no longer need the `games =` parameter
fed by targets (the week grid replaces it), but the parameter stays for
standalone use.

## Hypotheses / expectations

- After an interrupted refresh, re-running `tar_make()` executes only the
  failed/unstarted branches — completed weeks are never re-ingested.
- The combined tables are row-identical to the previous loop outputs, so
  downstream targets stay up to date after the next refresh (no value churn).

## Consequences

- First full refresh after adopting this costs the same ~1,150 calls (no
  branch cache yet); resumability pays off from every subsequent failure.
- Branch objects live in `_targets/objects/` under `format = "rds"`; ~1,200
  small tibbles add some disk use but nothing proportional to the parquet
  assets.
- Track mode is unaffected: grid/chunk targets return NULL there and the
  cleaned parquet assets are tracked files.

## Outcome / what we learned

_Filled in later._
