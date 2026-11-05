# 0034 — Season-scoped refresh: current-season runs, partitioned assets

- **Status:** Proposed
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
issue #46. This branch records the decisions and ships the calendar and selector
helpers only; wiring the ingest targets, partitioned assets, and workflows is
follow-up work (checklist below).

## Decision

### 1. Partitioning

Season-keyed cleaned tables are stored as one parquet file per season:
`data/<table>/season=YYYY.parquet`, read with `arrow::open_dataset()`.
Recommended over a `<table>_historical` + `<table>_current` pair because:

- The partition key is the same concept every source already has (`season`), so
  one scheme covers `games`, `player_stats`, `roster`, `recruiting`, `plays`, and
  so on. A pair would need a split rule per table and a re-merge on every
  rollover.
- A run replaces exactly the partitions it re-pulled. Rollover needs no data
  movement: the just-finished season simply stops being in the selector.
- Partial failures are visible per season (a missing `season=` file is a
  contract failure, not a silently short table).

Non-season tables (`teams`, `play_types`, `play_stat_types`, the dimension
lookups) stay as single files and ride the current slice. Derived tables
(`conference_tiers`, `outcomes`, `team_season`, `team_draft`, the DuckDB bundle)
are recomputed from all partitions on every run. That is local compute with no
API calls.

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
| `recruiting` | `current_season(date) + 1` | the incoming class; recruiting for class Y is published during Y-1's season (verified 2026-11-05: `/recruiting/players?year=2027` returned 2,942 recruits, 93% committed, but 28% still without a star rating vs 7–11% in finished classes, so the class is provisional until February signing day and re-pulling it weekly is the point) |
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

### 4. Calendar edge cases

- `current_season(date)`: `year(date)` if `month(date) >= 8`, else `year(date) - 1`.
  Aug 1 is the new season; Jul 31 is still the old one.
- January bowls and the national championship (early-to-mid January) belong to
  the **prior** season, which is what the rule gives.
- Seasons are keyed by the CFBD `year`, so spring games and recruiting-cycle
  dates do not move the season.

### 5. Schedule

- `data-current.yaml` (replacing the weekly full `data-refresh.yaml`): weekly
  from late August to mid January, plus runs after National Signing Day (early
  February), the combine (early March), and the draft (late April). Off-season
  runs are `workflow_dispatch` only.
- `data-raw/refresh-historical.R` (on demand, run locally where CFBD does not
  throttle): backfills a season range, prints the estimated call count, and
  requires confirmation before starting.
- `site.yaml` downloads the published assets and renders. No ingest.

### 6. Release layout

A single `data-latest` tag holds all partitions. Reasons: `pb_download()` needs
one tag for a fresh checkout; a two-tag split (`data-historical`,
`data-current`) forces every consumer to know which tag owns which season and
complicates rollover. Partition file names are unique per table and season, so
they do not collide in the flat release-asset namespace (the collision problem
decision 0018 raised for raw vs cleaned files does not recur). The audit history
CSV keeps being carried across runs as today.

### 7. Expected call cost of a current-season run

Estimated from the existing ingest call patterns (decisions 0028, 0029, 0031),
for one season:

| Source | Calls |
|---|---|
| `/games` (regular + postseason) | 2 |
| `/games/teams` (one per played week, both season types, ~15 weeks) | ~16 |
| `/games/players` (one per played week) | ~16 |
| `/stats/player/season` | 1 |
| `/roster` | 1 |
| `/recruiting/players` (next class) | 1 |
| `/coaches`, `/teams`, `/draft/picks` (non-season or cheap, refreshed) | ~3 |
| `/plays` (one per week) | ~16 |
| **Subtotal without `/plays` or `/plays/stats`** | **~40** |
| **Total with `/plays`** | **~56** |
| `/plays/stats` (per game, ~2,100 games) | excluded from the default run |

Both totals are under the ~100-call target. `/plays/stats` stays opt-in by season (decision
0031) and is not part of the default current run. nflverse sources cost no
CFBD calls.

## Hypotheses / expectations

- A current-season run costs under 100 CFBD calls, against ~780 for the full
  refresh today.
- Re-pulling one historical season reproduces its published partition (row
  counts and schema hash match), so partitions are interchangeable across runs.
- Derived tables rebuilt from all partitions give the same output as today's
  full refresh when the selector covers the whole window.

## Consequences

- Revises decision 0017: the publish step writes partitions, not whole-table
  files. Revises decision 0018 only in the layout of the cleaned asset; the
  parquet-equals-DuckDB-equals-dictionary rule still holds per season.
- Extends decision 0029: the games-family branching becomes the pattern for
  every season-keyed source.
- Contracts must check that every season in the window is present exactly once
  per table, and that a partial run does not silently drop seasons.
- The `season=` partition layout changes what `inst/data-model.md` and the
  dictionaries describe. Those documents need updating in the follow-up.

## Follow-up checklist

- [ ] Season-branch `picks`, `player_stats`, `coaches`, `roster`, `recruiting`, and the nflverse tables, using `refresh_seasons()` for the season vector.
- [ ] Read-published-partition vs ingest switch per branch, honoring `CFB2NFL_REFRESH_SEASONS`.
- [ ] Partitioned `parquet_asset()` writer and an `open_dataset()` reader; `build_duckdb()` reads the full partition set.
- [ ] Contracts: every season in the window present once per table; no silent partial-run gaps; current-slice row counts within bounds of the prior run.
- [ ] `.github/workflows/data-current.yaml` with the seasonal schedule; retire or demote `data-refresh.yaml`.
- [ ] `data-raw/refresh-historical.R` with call-count estimate and confirmation; update `data-raw/refresh.R`, `publish-data.R`, `pull-data.R`.
- [ ] Slim `site.yaml` to download and render.
- [ ] Update `AGENTS.md` (Data, quota, pipeline sections), `inst/data-model.md`, and `NEWS.md`.
- [ ] Verify the call-count estimate against a real current-season run before relying on it.

## Outcome / what we learned

_Filled in later._
