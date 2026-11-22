# NFL play, snap and roster-status data (2022 on)

Feature: F23 (all criteria). Builds toward F19 (thrive or fizzle).

**Status (2026-11-22):** card F23 is in `product/features.md` under G4;
reviews below.

Goal: give every drafted and UDFA player an NFL record of **what they did on
a play** (play-by-play, EPA), **whether they were on the field** (snap
counts, per-play participation, linemen included), and **where they stood on
the roster each week** (active, practice squad, inactive, injured reserve,
cut, traded). That supports later questions such as "did a high pick play
right away, have to earn it, or get hurt?" and attributing players'
contributions to game outcomes. The analysis method is open; this plan only
makes the data available. Sized 2026-11-22, decisions from the interview the
same day.

## 1. Decisions

| Decision | Choice | Why |
|---|---|---|
| Seasons | **2022 through the current season**, for every new NFL table | Only what the next investigations use. One constant widens it later. |
| CFB side | No CFBD backfill: `play_stats` stays 2026-only | Saves ~8,400 CFBD calls; college contribution comes from `plays` and game stats for now |
| Play-by-play columns | **Full** nflverse schema (372 columns) | The attribution method is undecided; 5 seasons fit (~150 MB DuckDB) |
| Presence | Snap counts (2022 to current) **and** participation (2022 to 2025) | Snaps cover the current season and every position; participation adds who was on the field per play (formation, personnel, routes) |
| Standing | Weekly roster status | Active, practice squad, inactive, IR, cut, traded, plus depth-chart position, one row per player-week |
| Not pulled | Injury reports, trades table | Weekly status already separates "hurt" (IR) from "not playing" and records `TRD`; add either later if a post needs it |
| Backfill run | **Dedicated `data-raw/refresh-nfl.R`** | Touches only the NFL targets, 0 CFBD calls |
| Tracking | New data feature **F23** under G4; F19 stays an idea built on it | F23 can ship once the data is published and contract-gated |

## 2. Sources (nflverse, no API key)

| Table | nflreadr | Grain | Key | Seasons available | Size / season (parquet, DuckDB) |
|---|---|---|---|---|---|
| `nfl_pbp` | `load_pbp()` | play (REG + POST) | `(game_id, play_id)` | 1999 to 2026, rebuilt nightly in season | 21.6 MB, 29.9 MB |
| `nfl_participation` | `load_participation()` | play | `(nflverse_game_id, play_id)` | 2016 to 2025; **2026 not published** (404 on 2026-11-22) | 4.7 MB, ~8 MB |
| `nfl_snap_counts` | `load_snap_counts()` | player-game | `(game_id, pfr_player_id)` | 2013 to 2026 (through week 11 today) | 0.24 MB, ~0.5 MB |
| `nfl_rosters_weekly` | `load_rosters_weekly()` | player-team-week | `(season, week, team, gsis_id)` | through 2026 week 11 today | 0.85 MB, ~1.5 MB |

Notes:

- Participation 2022 is the older NGS-sourced format; 2023 on comes from FTN
  with more fields (coverage type, routes, pressure). Columns absent in 2022
  are `NA` there.
- Participation keeps nflverse's shape: `offense_players` /
  `defense_players` are `;`-separated gsis ids per play. An analysis unpacks
  them to play x player on the fly (decision 0041).
- Weekly status values seen in 2025: `ACT` 27,377, `DEV` (practice squad)
  8,783, `RES` (reserve, mostly IR) 5,763, `INA` 3,593, `CUT` 951, `RET`
  361, `TRD` 7. A move between teams shows as a team change between weeks; it
  is reported as an event, never as a judgment about the player.

## 3. Joins to the model population

- `outcomes.gsis_id` already bridges drafted players (draft slot) and UDFAs
  (name-guarded roster match), so `nfl_pbp` (every `*_player_id`),
  `nfl_participation` (the id lists) and `nfl_rosters_weekly` join with no
  new linking.
- `nfl_snap_counts` is keyed by `pfr_player_id`. It reaches `gsis_id` through
  `nfl_draft_picks.pfr_player_id` for drafted players and through the
  `load_players()` pfr -> gsis crosswalk (`ingest_nfl_players()`) for UDFAs.
  The contract reports the share of snap rows that map to a gsis id.
- NFL data remains an outcome/label, off the in-career model path (decision
  0014).

## 4. Release capacity

GitHub release limits: each asset under 2 GiB (~2,147 MB), up to 1,000
assets, no limit on total size or bandwidth. The binding file is
`cfb2nfl.duckdb` (367.5 MB now; ~1,780 MB headroom). The stale
`cfbstats.duckdb` (82 MB) was deleted from the release and locally on
2026-11-22.

Added by this plan, 2022 to 2026:

| Table | DuckDB | Parquet asset |
|---|---|---|
| `nfl_pbp` (full) | ~150 MB | ~105 MB |
| `nfl_participation` (2022 to 2025) | ~32 MB | ~19 MB |
| `nfl_snap_counts` | ~2.5 MB | ~1.2 MB |
| `nfl_rosters_weekly` | ~7.5 MB | ~4.3 MB |
| **Total** | **~190 MB** | ~130 MB |

DuckDB goes from ~367 MB to ~560 MB. Yearly growth: CFB ~35 MB plus NFL
~40 MB (pbp 30, participation ~8 once published, the rest ~2), so ~75 MB a
year. **Years until 2 GiB: ~21** (~16 if CFB play volume keeps rising as it
did in 2022). Widening the NFL floor costs ~40 MB DuckDB per added season. In
memory, a full-column pbp splice holds ~1 GB at peak, fine on a 16 GB
runner. A site build downloads ~690 MB instead of ~560 MB.

## 5. Pipeline

1. `R/ingest.R`: `ingest_nfl_pbp()`, `ingest_nfl_participation()`,
   `ingest_nfl_snap_counts()`, `ingest_nfl_rosters_weekly()`, each taking
   `seasons` and clamping to seasons nflverse has published
   (`<= nflreadr::most_recent_season()`; participation additionally skips a
   season whose file is missing, with a message, instead of erroring).
2. `R/seasons.R`: add the four sources to `refresh_source_groups` as `nfl`
   (Aug 1 rule, so January and February playoffs stay in their season), and
   a per-source floor (`nfl_pbp_min_season <- 2022L`) passed as
   `min_season` so the full window is 2022 to current.
3. `R/clean.R`: `clean_nfl_pbp()` (types; REG + POST), `clean_nfl_participation()`,
   `clean_nfl_snap_counts()`, `clean_nfl_rosters_weekly()`.
4. `_targets.R`: for each, `raw_<t>` (`if (refresh_enabled())
   ingest_<t>(refresh_seasons(source = "<t>", min_season = 2022L))`), then
   `<t>_file` = `parquet_asset()` wrapping `splice_seasons(clean_<t>(raw_<t>),
   path, "season", seasons, full = refresh_is_full(...))`, then `<t>` read.
   Participation splices on a season it has; a current season with no
   published file leaves the table unchanged.
5. Contracts (`contract_gate`): unique keys; `season_coverage` 2022 through
   the last completed season (participation: through the last season
   nflverse published); gsis ids match `^00-00\\d{5}$`; `epa` in a plausible
   range; snap pct in [0, 1]; status in the known set. Bridge coverage
   (`contract_nfl_bridge()`): share of `outcomes` players with an NFL entry
   (`draft_year >= 2022`) found in weekly rosters, and share of snap rows
   mapping to a gsis id through a pipeline-stage target `nfl_players`
   (the `ingest_nfl_players()` pfr -> gsis crosswalk, which the explorer's
   `explorer_nfl_players` then reuses instead of pulling its own), each with
   a failing threshold recorded in the contract and the decision record.
6. Leakage test (testthat): walk `tar_network()` and fail if any of the four
   NFL tables is upstream of `model_table` or `model_fit`.
7. `inst/dict/*.yml` for the four tables, the
   `duckdb_file` table list, `inst/data-model.md` (grain, key, join path;
   coverage starts 2022 so earlier careers are truncated, use season-grain
   `nfl_rosters` for whole careers and longevity; current season partial;
   a worked query from `outcomes` to one named player's weekly status and
   snaps), audit rows, the AGENTS.md data table.
8. Decision record: "NFL play, snap and roster-status data from 2022,
   season-spliced, full pbp columns", with the bridge thresholds.
9. Publish before merging (track-mode CI needs the new parquet).

### Weekly current season, past seasons once

- **Weekly:** `data-current.yaml` (Sundays 13:17 UTC, Aug to Jan, plus
  Feb 8, Mar 10, May 2) runs with `current`. For the NFL sources that is the
  current NFL season: ~25 MB downloaded, 0 CFBD calls, the whole season
  replaced, which also picks up nflverse's nightly corrections. The Mar 10
  run still counts 2026 as current, so it captures the playoffs and Super
  Bowl. No schedule change needed.
- **Once:** `Rscript data-raw/refresh-nfl.R --yes --publish`, which pulls
  the full NFL window (2022 to current; `splice_seasons()` has no published
  file to splice into yet, so the first pull must be the full window). The
  script sets `CFB2NFL_REFRESH=true`, invalidates only the NFL `raw_*` and
  `*_file` targets and builds just those (`tar_make(names = ...)`), then
  runs a second `tar_make()` in **track mode** so the contracts, the DuckDB
  and everything downstream rebuild from the published parquet without
  touching CFBD (a refresh-mode build on a store with outdated `raw_*`
  targets would re-ingest every source). It reports the CFBD call count
  from `CFB2NFL_CALL_LOG` and stops if it is not 0. With `--publish` it
  uploads the NFL parquet and the DuckDB. Later seasons can be re-pulled
  with a selector (`refresh-nfl.R 2024`), for example after an nflfastR EPA
  model update.
- Participation for 2026 enters through the weekly run automatically once
  nflverse publishes it.

## 6. Feature card

The card is **F23** in `product/features.md` (under G4 · Follow players
into the NFL), the source of truth for its acceptance criteria.

## 7. Build checklist

Tracked in the F23 issue; task-reviewer 2026-11-22 (pre-build): gaps (5),
folded in below.

- [ ] Ingest (`R/ingest.R`, roxygen): `ingest_nfl_pbp()`,
  `ingest_nfl_participation()`, `ingest_nfl_snap_counts()`,
  `ingest_nfl_rosters_weekly()`, clamped to seasons nflverse has published.
- [ ] Seasons (`R/seasons.R`): the four sources in `refresh_source_groups`
  (`nfl`) with a 2022 floor. A selector that picks **no** season in the NFL
  window (e.g. `refresh-historical.R 2015`) skips the NFL sources (raw is
  `NULL`, the published parquet is kept) instead of aborting; testthat case
  for a pre-2022 selector. A CFB selector overlapping 2022 on (e.g.
  `2021:2023`) also re-pulls those NFL seasons, at 0 CFBD calls.
- [ ] Clean (`R/clean.R`, roxygen): each table conformed to its dict
  columns and types (missing columns added as `NA`, new nflverse columns
  dropped with a message), so a schema change upstream cannot break the
  weekly splice. Participation gets `season` from the game id.
- [ ] Targets: `raw_*`, `*_file` (spliced by season), table targets,
  `nfl_players` crosswalk target reused by `explorer_nfl_players` (a live
  nflreadr download in both modes; noted in the decision record).
- [ ] Contracts: per table (keys, ranges, id pattern, status set),
  `season_coverage` from 2022, and `contract_nfl_bridge()`: denominator =
  distinct players with `outcome_nfl_entry_d` TRUE on a row with
  `draft_year >= 2022` (one row per player, joined on non-NA `gsis_id`;
  entrants with no `gsis_id` reported); thresholds X (weekly rosters) and Y
  (snap rows -> gsis) set from the first backfill.
- [ ] Leakage test: no NFL table upstream of `model_table` / `model_fit`.
- [ ] `build_duckdb()` (or the publish step) aborts if the file is 2 GiB or
  more.
- [ ] `data-raw/refresh-nfl.R`: targeted refresh-mode build, then a
  track-mode build; stops before publishing if the CFBD call log is not 0 or
  if any non-NFL `data/*.parquet` md5 changed; prints per-season row counts
  for the four tables.
- [ ] `data-current.yaml`: write per-season row counts of the four NFL
  tables to the step summary (evidence that only the current season moved).
- [ ] Docs: `inst/dict/*.yml` (from nflreadr's dictionaries), DuckDB table
  list, `inst/data-model.md` (join paths, 2022 truncation, partial current
  season, longevity stays in `nfl_rosters`, worked query), AGENTS.md table,
  decision record with X and Y, NEWS.
- [ ] Release order: backfill and publish, then merge **before the next
  Sunday 13:17 UTC `data-current.yaml` run** (main's run would otherwise
  rebuild the DuckDB without the new tables), then dispatch `site.yaml` and
  confirm it passes with the larger download.

## 8. Order of work


1. F23 card reviewed (`feature-reviewer`), tasks reviewed (`task-reviewer`).
2. Branch `data/nfl-pbp` from `main`; TDD the ingest/clean functions on
   fixtures, then the contracts.
3. `data-raw/refresh-nfl.R`; run the backfill locally, publish.
4. NEWS, decision record, PR; `task-reviewer` on the diff.
