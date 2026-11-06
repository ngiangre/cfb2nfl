# 0037 — season arcs and opponent-adjusted game production as derived tables

- **Status:** Accepted
- **Date:** 2026-11-05

## Context

Issue #47 asks what a player's performance arc looks like across a college
career, and how much opponent strength should count when a game's production is
read. The player x game table (decision 0035) gives per-game usage and pregame
Elo for each opponent. Season totals already exist in `player_stats`. Both
questions would otherwise be re-derived in each vignette, which is the drift
risk decision 0021 removes.

## Decision

Add two derived tables, built by pure, tested functions and following the
decision 0021 recipe (target, contract in `contract_gate`, `audit_step()` row,
dictionary, `duckdb_file` entry, `data-model.md` row and ERD edge):

- **`season_arc`** (`build_season_arcs()`, `R/season_arc.R`). One row per
  `(playerId, season, category, statType)` for four headline stats: passing
  yards, rushing yards, receiving yards and tackles. Multi-team seasons are
  summed, and `team` names the larger share. `season_index` is the player's
  career season, counted over all stats, so an index means the same season in
  every arc. It starts at 1 at the first season in the data (2010 onward), so a
  career that began earlier is left-censored.
- **`game_production`** (`build_game_production()`, `R/game_production.R`). One
  row per `(playerId, gameId, stat)` for the passing, rushing and receiving
  yardage columns of `player_game`. The baseline is the mean value of that stat
  over player-games in the same season and opponent Elo band that have a line in
  that category. `residual = value - baseline`. The bands are Under 1400, 1400
  to 1599, 1600 to 1799, 1800 and up, and Unrated (no CFBD Elo, mostly FCS and
  lower-division opponents). Unrated is its own band, never dropped or imputed
  (the same stance as decision 0013 for unrated recruits).

The contracts enforce key uniqueness and no silent row loss: `season_arc` has
one row per numeric player-season-stat in `player_stats`, and `game_production`
has one row per non-`NA` yardage value in `player_game`. Both are checked in
`contract_gate`.

Neither table is published as parquet. Both rebuild from cleaned tables in any
mode, so track-mode builds need no release asset (decision 0021).

## Hypotheses / expectations

- The residuals center on zero within each (season, stat, band) group, by
  construction. The test suite checks this on a fixture.
- Opponent Elo is `NA` on about 27% of player-games (measured on the published
  data, 2026-11-05). The Unrated band therefore carries about 27% of rows and is
  reported as its own category.
- Raw passing yardage falls only modestly with opponent strength (about 16 yards
  per game from the weakest to the strongest rated band, measured on the
  published data).

## Consequences

- The opponent adjustment is against a league baseline for each stat, not
  against position: a passing baseline is every player with a passing line. A
  position-specific baseline is a follow-up.
- Athlete ids recycled across people (decision 0022) are not excluded from
  either table. The affected ids are about 0.1% of roster rows, so the effect is
  small, but a reuse-filtered input is a follow-up.
- NFL outcomes stay off both tables (leakage, decision 0014).

## Outcome / what we learned

_Filled in later._
