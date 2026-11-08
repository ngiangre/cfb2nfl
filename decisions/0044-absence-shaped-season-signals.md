# 0044 — Injury-shaped and benching-shaped season signals from complete box scores

- **Status:** Accepted
- **Date:** 2026-11-07

## Context

Issue #51 part 2 asks whether the data can tell an injured player from a benched
one. CFBD has no injury or depth-chart feed, so the only evidence is the shape
of a season in the per-game box scores (`game_player_stats`, decision 0035).
Building it exposed an ingest bug: `flatten_game_player_stats()` kept only the
first athlete in each team's stat type per game (`athlete$id[[1]]`), so the
published table held about 7 players per team-game instead of about 33 (from
2016, when CFBD box scores begin listing defensive stats). Every game-level
number built on it (playing time, decision 0038; game production for the
performance-arcs post) undercounted players.

## Decision

- Fix the flatten to keep every athlete, re-pull `/games/players` for the full
  window (279 CFBD calls) and republish `game_player_stats.parquet` and the
  DuckDB bundle on `data-latest`. `contract_game_player_stats()` now requires
  most team-games (with 100 or more in the table) to list more than one rusher,
  so a one-player-per-stat-type table fails the gate.
- Read two season shapes, both heuristics and neither a label (decision 0039's
  rule for the early-stop proxy applies):
  - **Injury-shaped absence** (`absence_runs()`): a regular, with a stat line in
    three straight team games, who then has none in two or more straight games;
    `returned` or `season_ending`. Team games with no box score for anyone on
    the team are dropped, not read as misses.
  - **Benching-shaped decline** (`usage_decline()`): six or more games appeared,
    a starter's first-half usage (one count per position, `usage_signal_map()`),
    and a second-half mean at half or less. Offensive line and special teams have
    no usage count, so the signal cannot reach them.
- Both are built on the fly in the post that uses them (decision 0041), on
  2016 to 2025 (the seasons with defensive box scores).

## Hypotheses / expectations

- The box score can read an absence only for players who log stats, so almost
  no offensive lineman's season is readable.
- Declines are rarer than absences among the seasons that can show each.
- Early-stop careers end in a season-ending absence more often than careers that
  used up their eligibility; the gap may be small, since most early stops are
  not regulars in their final season.

## Consequences

- Posts built on the earlier box scores (playing time, performance arcs) need
  re-rendering; their frozen numbers predate the fix.
- Any writing on these signals says "injury-shaped" or "benching-shaped" and
  names what else produces the same shape.
- Validating either rule needs an external injury source, which is out of
  scope (issue #51) and would need its own ingest and name guard.

## Outcome / what we learned

_Filled in later._
