# Plan: publish the game-statistics tables (CFBD /games family)

Status: code complete, blocked on API quota. Next action is a local refresh
run on/after the monthly quota reset.

## State of play

The integration (ingest → clean → contracts → targets → dicts → docs) is done
and green locally: 343 tests pass, `air format --check` clean, `check()` 0
errors/0 warnings (two pre-existing local-only notes). What remains is
publishing the data and the release/CI choreography.

- Tables: `games` (one row per game), `game_team_stats` (team-game-category-stat),
  `game_player_stats` (player-game-category-statType-stat). All long-grain,
  matching the `player_stats` convention.
- `game_player_stats.playerId` is the shared athlete-id namespace — joins the
  career backbone with no name guard. `games.id` == `gameId` is the new
  game-level namespace.
- New dictionaries: `inst/dict/games.yml`, `game_team_stats.yml`,
  `game_player_stats.yml`; [inst/data-model.md](../inst/data-model.md) updated
  (table rows, ERD lines, join namespace 6, games-played example query).

## Quota facts (learned 2026-10-17)

- The API key was on the **free tier: 1000 calls/month**. The failed refresh
  burned most of it (full `/games` sweep, most of `/games/teams`, part of
  `/games/players`, plus sizing probes); a single request still 429'd after a
  5-minute cooldown, confirming a long window, not a burst window.
- **Key has been upgraded to 5000 calls/month.** Wait for the monthly reset
  (or the upgrade to take effect) before re-running.
- One full refresh now costs roughly: game family ~630 calls (`/games` ~34,
  `/games/teams` ~300, `/games/players` ~300 across 2010–2026, both season
  types) + ~60 for the rest of the refresh ≈ **700 calls per refresh**.
  Monthly refreshes (7 runs) fit inside 5000 with headroom, but re-running a
  *failed* refresh costs the full ~700 again.

## Steps

1. **Re-run the refresh locally** once the quota is live:
   `CFBSTATS_REFRESH=true Rscript data-raw/refresh.R`.
   The game-family calls are paced (1 call / 2 s via `cfbd_game_get()`,
   10-try/600 s retry budget) so the sweep should take ~25–30 min and not die
   mid-way. Verify `data/games.parquet`, `game_team_stats.parquet`,
   `game_player_stats.parquet` are written and the contract gate passes.
2. **Do NOT re-run blindly on failure.** Each attempt costs ~700 calls. If it
   fails again, inspect `tar_make()` output first; consider hand-running
   `ingest_game_*()` for the missing seasons only and reusing targets caching.
3. **Publish** per the usual flow: `piggyback::pb_upload(...,
   tag = "data-latest", overwrite = TRUE)` (the same upload the CI job runs),
   then re-dispatch `site.yaml` via the `gh` R package.
4. **Before merging, update NEWS.md** with the new tables (decision 0007),
   squash-merge the feature branch, and record a decision entry (copy
   `decisions/TEMPLATE.md`, next number) covering: the `/games` family
   integration, the pacing/retry amendment to the game endpoints (decision
   0028 otherwise unchanged), and the quota constraint that motivates per-call
   economy.
5. **Post-publish checks:** `tests/testthat/test-dict.R` must now validate the
   three new dicts against the published parquet (currently skips while
   `games.parquet` etc. are absent locally); run `tar_make()` in track mode to
   confirm a fresh checkout builds; confirm the DuckDB bundle carries the three
   tables (`_schema_manifest` shows them as `documented = TRUE`).

## Follow-ups (not blockers)

- If refreshes keep failing mid-sweep, split the game ingests into per-season
  targets so a failure resumes instead of re-pulling all seasons (~700 calls
  at stake per retry).
- The weekly scheduled CI refresh in `data-refresh.yaml` now makes ~700 calls
  against a 5000/month budget — verify the schedule cadence keeps the month
  under budget, and remember CI shared-runner IPs are 503-prone (the local
  fallback stands).
- Update the project memory (AGENTS.md) data table with the three new tables
  once published.
