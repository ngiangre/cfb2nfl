# 0031 — Plays ingest: two grains, per-game play-stats, and quota phasing

- **Status:** Accepted
- **Date:** 2026-10-22

## Context

We want play-by-play data (CFBD `/plays` family) to enrich the player
trajectory feature set: PPA, usage attribution, and situational context that
box-score season stats cannot express. Constraints discovered by probing
(2026-10-22):

- `/plays` has **no row cap at the week grain** (22,320 rows for one week) and
  costs **one call per (year, week, seasonType)** — ~20 calls/season.
- `/plays/stats` (player-level, carries `athleteId`) is **hard-capped at
  2,000 rows per query** on the week grain; only per-`gameId` queries return a
  complete game (~230 rows). At ~2,100 games/season this is ~2,100 calls per
  season, ~36k calls for 2010-2026 — far beyond the 5,000/month quota.
- `/live/plays` returns **401 Unauthorized** on this key's tier.
- `/plays/stats.athleteId` was validated against the shared namespace: all 323
  distinct ids from a probe week are in `roster$playerId` and every id-name
  pair matches `player_stats$player` (100%). No name guard needed.
- `/plays/types` (49 rows) and `/plays/stats/types` (31 rows) are static
  dimension lookups, one call each.

## Decision

1. **Four new cleaned tables**: `play_types`, `play_stat_types` (static
   dimensions), `plays` (one row per play, key `id`), `play_stats` (one row
   per athlete-play-stat, key `(playId, athleteId, statTypeId)`). Long grain,
   same conventions as the rest of the pipeline.
2. **`/plays` is ingested at the week grain** (one call per week/seasonType,
   weeks from the ingested `games` table via `weeks_for_year()`).
3. **`/plays/stats` is ingested at the game grain** (per `gameId`) — the only
   query unit that avoids the 2,000-row truncation. DAG branching is at
   **season** grain (decision 0029); games are looped inside the chunk, since
   game-grain branching would mint ~2,100 targets per season.
4. **Phased rollout to respect the 5,000-call/month quota**: Phase 1 is the
   dimensions + full `/plays` backfill (~360 calls, one refresh). Phase 2 is
   `/plays/stats` backfilled **one season per refresh**, newest first
   (2021+ first — draft classes from 2013 on carry near-100% athlete ids),
   behind an opt-in `CFBSTATS_PLAYS_STATS=true` flag so the standard refresh
   never silently spends ~2,100 calls.
5. **`/live/plays` is out of scope** — 401 on this tier. Do not re-probe.
6. Contracts: `plays$gameId ⊆ games$id` + per-week coverage; `play_stats`
   athleteId namespace-coverage check; truncation/cap detection; schema
   stability — all wired into the `contract_gate` (decision 0023).

Alternatives not picked: week-grain `/plays/stats` pulls (silently truncated);
per-team-week chunking (2 calls/game for the same information, more calls);
game-grain dynamic branching (target explosion); skipping the dimensions
(needed for display and statTypeId stability).

## Hypotheses / expectations

- Phase 1 (plays without athlete attribution) already yields useful
  team-context and situational features; Phase 2 unlocks player-level
  usage/PPA features that improve the drafted forecast beyond box-score stats.
- The athleteId namespace match holds across seasons, not just the probe week;
  the contract gate will catch it if it doesn't.
- Per-season Phase 2 pulls (~2,100 calls) fit the monthly budget alongside the
  ~780-call base refresh; two seasons in one month does not.

## Consequences

- +4 tables in the DuckDB bundle, dicts, data-model.md, and the `data-latest`
  release; Phase 1 parquet must be published before merging so track-mode
  builds work.
- Refresh wall time grows by ~6 min (Phase 1) and ~70 min per Phase-2 season.
- Play-derived features are in-career inputs; the out-of-time validation rule
  (never see seasons on/after the predicted draft class) applies unchanged.
- If CFBD lifts the 2,000-row cap or raises the tier, the per-game strategy
  can be revisited; the ingest functions, not the DAG, own that choice.

## Outcome / what we learned

_Filled in later._
