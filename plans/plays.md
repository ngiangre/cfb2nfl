# Plan: incorporate CFBD play-by-play (the /plays family)

Status: design validated (probes + namespace check done 2026-10-22), code not
started. Decision 0031 records the ratified choices.

## What the endpoints are (probed 2026-10-22)

| Endpoint | Response | Grain / key | Notes |
|---|---|---|---|
| `/plays/types` | 49 rows | play-type dimension (`id`, `text`, `abbreviation`) | static; 1 call |
| `/plays/stats/types` | 31 rows | play-stat-type dimension (`id`, `name`) | static; 1 call |
| `/plays` | ~22,320 rows for week 1 of 2024 (133 games) | one row per play; `id` (string) joins `gameId`; `ppa`, `clock` (secs), `wallclock`, down/distance, `yardsToGoal`, `playText` | **no row cap at the week grain** — 1 call per (year, week, seasonType) |
| `/plays/stats` | player-level: `athleteId` (string), `athleteName`, `statType`, `stat`, game/drive/play context | one row per athlete-play-stat | **hard cap of 2,000 rows on the week grain** (10 of 133 games returned); must query per `gameId` (~230 rows/game) |
| `/live/plays` | **HTTP 401 Unauthorized** | — | not accessible on this key's tier; skip |

## Namespace validation (done 2026-10-22, pass)

From the 2024 week-1 `/plays/stats` pull: all **323** distinct `athleteId`
values are present in `roster$playerId`, and every id-name pair agrees with
`player_stats$player` (14,867 comparisons, 100% match). `athleteId` is the
shared athlete namespace — joins need **no name guard**, unlike recruiting
(decision 0013). The contract gate should still assert coverage so a future
CFBD change fails loudly rather than silently dropping rows.

## Tables

| Table | Grain | Key | Joins |
|---|---|---|---|
| `play_types` | one play type | `id` | `plays.playTypeId` display dim |
| `play_stat_types` | one play-stat type | `id` | `play_stats.statTypeId` display dim |
| `plays` | one play | `id` (string) | `gameId` ⊆ `games$id` |
| `play_stats` | one athlete-play-stat | `(playId, athleteId, statTypeId)` | `athleteId` == shared playerId namespace |

All flat; long grain consistent with `player_stats` / `game_player_stats`.

## Ingest design

- `ingest_play_types()`, `ingest_play_stat_types()`: single calls.
- `ingest_plays(years, games)`: map over `(year, week, seasonType)` from
  `weeks_for_year()` (reuse ingested `games`, no re-pull); `cfbd_game_get()`
  pacing (1 call/s) + 10-try/600 s retry budget. ~20 calls/season → ~340 calls
  for 2010-2026.
- `ingest_play_stats(years, games)`: map over **`gameId`** (the only unit that
  avoids the 2,000-row cap). Branch at **season** grain in the DAG (decision
  0029); loop games inside the chunk — game-grain dynamic branching would mint
  ~2,100 targets/season. ~2,100 calls/season (~70 min at 1 call/s).

## Quota phasing (the real constraint: 5,000 calls/month)

- **Phase 1 (one refresh, ~360 calls):** the two dimensions + full `/plays`
  backfill 2010-2026. Delivers play-level team context, PPA, play-type and
  situational features without the athlete bridge.
- **Phase 2 (staged across refreshes, ~2,100 calls/season):** `/plays/stats`
  for recent seasons first (2021+ covers draft classes with near-100%
  `collegeAthleteId` coverage, decision 0003), walking backwards as quota
  allows. Gate behind an opt-in env flag (`CFBSTATS_PLAYS_STATS=true`) so the
  standard refresh never burns the month's quota by accident. Budget: a
  monthly refresh is ~780 calls today; one Phase-2 season pushes a month to
  ~2,900 — feasible, two seasons is not.
- `/live/plays`: do not retry; recorded as tier-restricted (decision 0031).

## Steps

1. Feature branch `data/plays`. Add `ingest_play_*()` in `R/ingest.R`
   (+ a `cfbd_play_get()` alias with the game-family throttle if the pacing
   matches), `clean_*()` as needed (flatten only; responses are already flat),
   and a Phase-2 env flag in the ingest functions.
2. Add the four `parquet_asset()` targets + readers to `_targets.R`; add the
   four tables to `build_duckdb()`'s table list.
3. Dictionaries: `inst/dict/{play_types,play_stat_types,plays,play_stats}.yml`;
   update `inst/data-model.md` (join namespaces: `plays.gameId` → `games$id`;
   `play_stats.athleteId` → playerId namespace).
4. Contracts (`R/contracts.R`, wired into the `contract_gate`):
   - `plays$gameId ⊆ games$id`; every played week in `games` has plays.
   - `play_stats$athleteId ⊆ roster playerId` coverage threshold.
   - cap-detection: assert no gameId looks truncated in `play_stats`
     (re-pull spot check / count-vs-plays plausibility bounds).
   - schema stability + value ranges as usual.
5. testthat tests for the flatteners and the env flag; fixtures for the
   contract tests (no live calls in CI).
6. **Publish Phase 1 parquet before merging** so track-mode CI/site builds
   find the files (the `*_file` target errors otherwise).
7. Update NEWS.md (decision 0007), squash-merge, re-dispatch `site.yaml`.

## Downstream candidate features (input side, no leakage)

- Per athlete-season PPA accumulated from `play_stats` x `plays.ppa`
  (usage-weighted, not just counting stats).
- Attribution counts (targets, carries, pressures) from `play_stats.statType`
  — richer than pivoted box-score categories.
- Situational splits (down/distance/score state) per player-season.
- Play-type distributions per team as context features.

Model map note: play-derived features are **in-career inputs** — safe for the
out-of-time validation design as long as only seasons up to a draft class are
used (same rule as the rest of the feature path).
