# 0049 — NFL play, snap and roster-status data from 2022, season-spliced

- **Status:** Accepted
- **Date:** 2026-11-22

## Context

The NFL side of the data (decision 0014) is season-grain: roster seasons for
longevity, box-score season totals, a PFR career summary. That cannot show
whether a drafted or undrafted player thrived or fizzled: it has no EPA, no
playing time, nothing for linemen, and no week-by-week standing (did a high
pick play right away, have to earn it, or get hurt?). Feature F23 (goal G4)
adds the play-level data that question needs; F19 builds the analysis on it.

nflverse publishes four sources that cover it, with no API key and no CFBD
calls. Sizes measured 2026-11-22 (2025 season):

| Source | Grain | Per season (parquet, DuckDB) |
|---|---|---|
| `load_pbp()`, all 372 columns | play | 21.6 MB, 29.9 MB |
| `load_participation()` | play | 4.7 MB, ~8 MB |
| `load_snap_counts()` | player-game | 0.24 MB, ~0.5 MB |
| `load_rosters_weekly()` | player-team-week | 0.85 MB, ~1.5 MB |

GitHub release assets must each be under 2 GiB, with no limit on a release's
total size. The binding file is `cfb2nfl.duckdb` (367.5 MB before this
change), which bundles every table.

## Decision

1. **Four new published tables**, `nfl_pbp`, `nfl_participation`,
   `nfl_snap_counts`, `nfl_rosters_weekly`, from **2022** through the current
   NFL season (`nfl_play_min_season`): the seasons the next investigations
   use. Widening the window is one constant plus a full NFL pull.
2. **Every play-by-play column is kept** (the user's call): the method for
   attributing contributions to game outcomes is still open, and five
   seasons fit (about 150 MB of DuckDB). Weekly rosters keep 17 of nflverse's
   36 columns (cross-platform ids, headshots and physicals dropped; physicals
   are in `nfl_rosters`). Injury reports and the trades table are not pulled:
   weekly status already separates injured reserve from inactive and records
   `TRD`.
3. **Each table is conformed to its dictionary** (`conform_to_dict()`), so a
   column nflverse adds mid-season is dropped with a message instead of
   making `splice_seasons()` refuse the weekly refresh. The dictionaries are
   generated from nflreadr's own (`data-raw/make-nfl-dicts.R`).
4. **Season splice, NFL window.** The tables follow `CFB2NFL_REFRESH_SEASONS`
   inside their own window (`nfl_refresh_seasons()`): the weekly
   `data-current.yaml` run replaces the current NFL season, picking up
   nflverse's nightly corrections. A selector naming no season from 2022 on (a
   college backfill of 2015) leaves them as published (`parquet_asset()`
   keeps the file when the build returns `NULL`) instead of aborting.
5. **A dedicated, CFBD-free entry point**, `data-raw/refresh-nfl.R`: a
   refresh-mode build of only the NFL targets, then a track-mode build of
   everything downstream. It stops before publishing if the CFBD call log is
   not empty or any non-NFL parquet changed. The first pull is the full
   window, since a splice needs a published table to splice into.
6. **Bridge contract** (`contract_nfl_bridge()`): at least **99%** of NFL
   entrants from 2022 on (distinct players with `outcome_nfl_entry_d` on a
   row with `draft_year >= 2022`, joined on non-NA `gsis_id`) appear in
   `nfl_rosters_weekly`, and at least **99%** of snap-count rows map to a
   `gsis_id` through the nflverse pfr -> gsis crosswalk (`nfl_players`, now a
   pipeline target the explorer reuses; a live nflreadr download in both
   modes). First backfill: 100% of 2,288 entrants with a `gsis_id` (7 more
   have none), and 99.88% of snap rows.
7. **Leakage test**: no play-level NFL table may be upstream of `model_table`
   or `model_fit` (decision 0014).
8. `build_duckdb()` aborts when the bundle reaches 2 GiB, so an oversized
   bundle fails the build rather than the upload.

## Hypotheses / expectations

- `cfb2nfl.duckdb` grows to about 560 MB and then about 75 MB a year (35 MB
  college, 40 MB NFL), reaching 2 GiB in roughly 21 years (about 16 if
  college play volume keeps rising as it did in 2022).
- Participation arrives some time after a season ends; the season-coverage
  contract requires it only through two seasons back.
- A weekly run changes only the current NFL season's rows.

## Consequences

- Careers that began before 2022 are truncated in these tables; season-grain
  `nfl_rosters` remains the longevity source.
- A site build downloads about 130 MB more, and the full-column splice holds
  about 1 GB in memory at peak.
- Merge only after publishing, and before the next Sunday `data-current.yaml`
  run: main's refresh would otherwise rebuild the DuckDB without the new
  tables.

## Outcome / what we learned

_Filled in later._
