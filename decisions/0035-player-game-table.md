# 0035 — player × game is a derived table at the (playerId, gameId) grain

- **Status:** Accepted
- **Date:** 2026-11-05

## Context

The `/games` family (decision 0029) gives a long box score: one row per
player-game-category-statType-stat. Two open questions need a player-game
grain: per-game usage with games appeared over team games (#50), and
opponent-adjusted game performance (#47). Both would otherwise re-pivot the
1.47M-row long table and re-join `games` in each vignette, which is the drift
risk decision 0021 removes.

## Decision

Add `player_game` as an in-pipeline derived table, built by the pure function
`build_player_game(game_player_stats, games)` (`R/player_game.R`), following the
decision 0021 recipe: target, `contract_player_game()` in `contract_gate`,
`audit_step()` row, `inst/dict/player_game.yml`, `duckdb_file` entry, and a
`data-model.md` row and ERD edges. It is bundled into DuckDB and not published as
parquet, since it rebuilds from the cleaned game tables in any mode.

- **Grain:** one row per `(playerId, gameId)` that has at least one stat line in
  `game_player_stats`, in any category. A kicker-only line still gets a row, so
  no player-game is dropped for lacking a usage stat.
- **Team and opponent context** come from `games` (joined on `gameId == id`):
  side, opponent and conferences, points, pregame Elo, neutral-site flag. The
  side is the box-score `homeAway`, verified to agree with the team name on every
  row.
- **Usage columns** are one wide double column per counted line (passing
  completions and attempts split from `C/ATT`, yards, touchdowns, interceptions,
  carries, receptions, tackles, solo tackles, TFL, sacks). A column is `NA` when
  the player had no line in that category in that game, and `0` when a zero was
  recorded. Yardage is signed (sacks and rushing losses) and is checked as a range.
- **`team_games`** is the team's games played in the season, from the existing
  `team_record(games)` (completed games with scores, all divisions, postseason
  included). Games appeared over team games is therefore a per-team-season
  participation rate, computed on the same definition as `team_season`.
- **NFL outcomes are kept off this table** (leakage, decision 0014).

The contract enforces key uniqueness, that every `gameId` is in `games`, and
no silent row loss (output rows equal distinct `(playerId, gameId)` in
`game_player_stats`). Elo `NA` is allowed and reported through the audit row,
not failed.

Alternatives not picked: keeping the long table and pivoting in each vignette
(the drift risk above); a player × game × category wide table (one row per
category is what the long table already is); publishing a parquet asset (no
refresh is needed, and the decision 0021 reasoning applies).

## Hypotheses / expectations

- The table is row-complete: 264,865 rows, equal to the distinct
  `(playerId, gameId)` pairs in `game_player_stats` (checked on the published
  data).
- Pregame Elo is `NA` on about 26% of player-games (team side) and 27%
  (opponent side). Nearly all of these are FCS and lower-division games, which
  CFBD does not rate. The rate is expected to be stable across refreshes.
- Every game in `game_player_stats` joins to `games` (verified: 0 unmatched).

## Consequences

- `build_player_game()` is ~2 s on the full table; the target is cheap to
  rebuild.
- #50 can compute games appeared over `team_games` directly; #47 can join
  opponent Elo without re-joining `games`.
- Any downstream model that uses these columns must treat Elo `NA` as its own
  category, not impute it (consistent with decision 0013's stance on unrated
  recruits).
- A future snap-count or play-level table (#44) would be a separate grain and
  table; this one does not try to be usage-by-snap.

## Outcome / what we learned

_Filled in later._
