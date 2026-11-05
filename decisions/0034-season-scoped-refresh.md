# 0034 — Season-scoped refresh: current-season runs spliced into one release

- **Status:** Accepted
- **Date:** 2026-11-05

## Context

Every refresh re-pulls 2010–2026 for every source (decision 0017's `refresh.R`
invalidates everything; `data-refresh.yaml` runs a full refresh weekly). That
costs ~780 CFBD calls per run against a 5,000/month quota, takes 10+ minutes,
and is fragile under CFBD 503s from shared runner IPs, while only the current
season actually changes. Heavier sources (play-by-play, #44: ~340 calls for
`/plays`, ~2,100 per season for `/plays/stats`; combine, #45) cannot be
refreshed on a sensible cadence at all under the current design.

This entry revises decisions 0017 and 0018 (the single full-table asset per
table, invalidated wholesale) and extends decision 0029 (branching by season
for the games family) to every season-keyed source. It implements the design in
issue #46.

## Decision

### 1. Season splice into one file per table (revised from partitions)

The draft of this decision proposed per-season partition files
(`data/<table>/season=YYYY.parquet`). Built instead: each published cleaned
table **stays one parquet**, and a season-scoped run **splices** the re-pulled
seasons into it (`splice_seasons()`, `R/seasons.R`): the fresh cleaned rows
replace exactly those seasons' rows, every other season is kept as published.
Reasons for the revision:

- GitHub release assets are a flat namespace with no directories, so partitions
  would be ~200 assets named like `roster-2024.parquet`, and every consumer
  (`build_duckdb()`, the readers, the site download, the dictionaries, the data
  model) would change. The splice changes none of them.
- The call savings are identical: only the selected seasons are ingested.
- Partial failures stay loud. Guards abort before anything is written: the
  published file must exist, the fresh rows must have the published columns (a
  schema change needs a full refresh), and no refreshed season may shrink below
  50% of its published rows (a truncated pull cannot replace good data). The
  `season_coverage` contract then requires every season from 2010 through the
  last completed one in each season-keyed table.

Season-keyed and spliced: `player_stats`, `roster`, `recruiting` (`hs_class`,
re-deduped to one row per athlete with `dedupe_recruiting()`), `games`,
`game_team_stats`, `game_player_stats`. Pulled in full every run because they
are one call each or free: `picks`, `coaches`, `teams` (CFBD, 3 calls) and the
nflverse tables (no CFBD calls). Derived tables (`conference_tiers`,
`outcomes`, team tables, the DuckDB bundle) are recomputed from the spliced
tables every run, locally.

### 2. Selector: `CFB2NFL_REFRESH_SEASONS`

Read by `refresh_seasons()` (see `R/seasons.R`). Accepted forms:

| Value | Meaning |
|---|---|
| unset or `""` | the full window for the source (today's behavior) |
| `current` | the season `refresh_season_for(source)` maps to today |
| `2024` | one season |
| `2010:2025` | an inclusive range |
| `2021,2023,2024` | a comma list (may mix singles and ranges, e.g. `2021,2023:2025`) |

Validation: anything else aborts with a `cli` error naming the bad token.
Results are clamped to the source's available window (`min_season` to the
source's maximum season), with a warning when a requested season falls outside.
Ranges are validated for `from <= to`.

Composition with `CFB2NFL_REFRESH`: the selector only has effect in refresh
mode. In track mode (`CFB2NFL_REFRESH` unset) the selector is ignored, so the
keyless site build can never spend calls. A refresh with `CFB2NFL_REFRESH=true`
and no selector keeps today's full-window behavior. Only an explicit selector
narrows a refresh.

### 3. Per-source "current" season

`refresh_season_for(source, date)` maps each source to the season the
`current` selector means.

| Source | Season | Rule |
|---|---|---|
| CFB season data (`games`, `game_team_stats`, `game_player_stats`, `player_stats`, `roster`, `coaches`, `plays`, `play_stats`) | `current_season(date)` | Aug-to-Jul year (see §4) |
| `recruiting` | `current_season(date)` | the class enrolled this season (revised from the incoming class, see below) |
| `picks`, `nfl_draft_picks`, combine | `draft_season(date)` | the most recently completed draft; the new draft year takes over on **May 1** (the draft is late April) |
| `nfl_rosters`, `nfl_player_stats` | NFL season | the NFL season runs Sep–Feb; use the same Aug cutoff, which lands on the prior season in Jan–Jul |
| `teams` (non-season) | none | rides the current slice, no season key |

Draft-keyed sources (picks, nfl_draft_picks, combine) are keyed by the **draft
year**, so the season they refresh is the most recently completed draft:
`draft_season(date) = year(date)` on or after May 1, else `year(date) - 1`.
Examples: 2026-03-01 gives 2025 (the April 2025 draft is complete); 2026-05-10
gives 2026 (the April 2026 draft just finished); 2026-11-05 gives 2026. This
differs from `current_season(date)` only in May–July, when the draft is done but
the college season has not started. The spec's "draft year = current_season() + 1"
is not used because it would refresh a draft that has not happened yet.

**Recruiting is the enrolled class, not the incoming one.** The draft used
`current_season() + 1`. The incoming class is published in-season (2026-11-05:
`/recruiting/players?year=2027` returned 2,942 recruits), but **0 of 2,942
carry a CFBD athlete id**: ids are assigned on enrollment, and
`clean_recruiting()` keeps only recruits with an id (the shared namespace,
decision 0003). So that call added no rows. The class that changes during a
season is the enrolled one, as its athletes get ids.

### 4. Calendar edge cases

- `current_season(date)`: `year(date)` if `month(date) >= 8`, else `year(date) - 1`.
  Aug 1 is the new season; Jul 31 is still the old one.
- January bowls and the national championship (early-to-mid January) belong to
  the **prior** season, which is what the rule gives.
- Seasons are keyed by the CFBD `year`, so spring games and recruiting-cycle
  dates do not move the season.

### 5. Schedule and entry points

- `.github/workflows/data-current.yaml` (scheduled): downloads every published
  asset, runs `tar_make()` with `CFB2NFL_REFRESH_SEASONS=current`, publishes
  with `overwrite = TRUE`, and dispatches `site.yaml`. Sundays August through
  January, plus Feb 8 (after National Signing Day), Mar 10 (after the combine),
  and May 2 (after the draft). `workflow_dispatch` takes any selector.
- `.github/workflows/data-refresh.yaml`: demoted to `workflow_dispatch` only,
  the full rebuild (~780 calls) for schema changes.
- `data-raw/refresh-historical.R <selector> [--yes] [--publish]` (local, on
  demand): prints `estimate_refresh_calls()` and refuses to start without
  confirmation; reports the calls actually made. `data-raw/refresh.R` stays the
  full rebuild and also reports its call count.
- Calls are counted through `CFB2NFL_CALL_LOG` (`cfbd_log_call()`, one line
  per request; retries inside a request are not counted).
- `site.yaml` downloads the release and runs `tar_make()` in **track mode**
  (no key, no API calls) so the audit/DAG pages have targets to read. Shipping
  the targets store to skip that compute was not done; the build already needs
  no `CFBD_API_KEY`.
- The stats ingests pull only weeks with at least one completed game, so an
  in-season run skips scheduled-but-unplayed weeks.

### 6. Release layout

A single `data-latest` tag holds every asset, one parquet per table as before.
A two-tag split (`data-historical`, `data-current`) would force every consumer
to know which tag owns which season and complicate rollover. Season rollover
needs no action: on August 1 `current` moves to the new season and the
finished one is simply no longer re-pulled. The audit history CSV keeps being
carried across runs.

### 7. Call cost of a current-season run

Measured 2026-11-05 with `data-raw/refresh-historical.R current --yes`:
**28 CFBD calls** (estimate 24, from the published games' 8 completed weeks; 10
were complete by then), against ~780 for a full refresh. Breakdown: `/games` 2,
`/games/teams` 10, `/games/players` 10, `/stats/player/season` 1, `/roster` 1,
`/recruiting/players` 1, `/draft/picks` + `/coaches` + `/teams` 3. Week-level
stats grow by one call each per played week, so a late-season run is ~35 and
a bowl-season run ~40. `/plays` (#44) would add about one call per week.

## Hypotheses / expectations

- A current-season run costs under 100 CFBD calls, against ~780 for the full
  refresh today.
- Re-pulling one historical season reproduces its published rows (row counts
  and schema hash match), so a splice is interchangeable with a full refresh.
- Derived tables rebuilt from the spliced tables give the same output as today's
  full refresh when the selector covers the whole window.

## Consequences

- Revises decision 0017: a refresh may now rewrite only some seasons of a
  published table. Decision 0018 is unchanged: parquet == DuckDB == dictionary
  schema, one cleaned asset per table.
- Extends decision 0029: every season-keyed CFBD source ingests only the
  selected seasons; the games family keeps its per-week branching.
- A splice can differ from a full re-clean in one place: recruiting dedupe sees
  only each athlete's previously kept record, so a refreshed record that drops
  below one the published table had already discarded wins anyway. A full
  refresh resolves it.
- New sources (#44 plays, #45 combine) should declare a season column and use
  `splice_seasons()` in their `*_file` target.

## Outcome / what we learned

- The first real current-season run (2026-11-05, local, not published) cost 28
  calls and replaced 2026 rows only: `game_player_stats` 92,559 → 103,277 2026
  rows, `player_stats` 144,711 → 149,725, other seasons untouched; every
  contract, including `season_coverage`, passed.
- The incoming recruiting class has no athlete ids until enrollment (above).
- The `build_outcomes()` UDFA name join is many-to-many by design; it only
  warned in refresh mode, now silenced with an explicit `relationship`.
