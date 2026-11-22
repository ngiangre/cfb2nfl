# NFL play, snap and roster-status data (2022 on)

Feature: F22 (all criteria). Builds toward F19 (thrive or fizzle).

**Status (2026-11-22): on hold.** Waiting for the `sdlc-alignment` work (the
`product/` registry and the reviewer agents) to land on `main`. Then: move
the F22 card into `product/features.md`, re-run `feature-reviewer` on it,
run `task-reviewer` on section 5, and only then start building.

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
| Tracking | New data feature **F22**; F19 stays an idea built on it | F22 can ship once the data is published and contract-gated |

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
   range; snap pct in [0, 1]; status in the known set; join coverage: share
   of `outcomes` players with an NFL entry season >= 2022 who appear in
   weekly rosters, and share of snap rows mapping to a gsis id, each with a
   failing threshold set from the first backfill (catches a broken bridge).
   A leakage test fails if any NFL table is upstream of a model-input
   target (walk `tar_network()`).
6. `inst/dict/*.yml` for the four tables, the `duckdb_file` table list,
   `inst/data-model.md`, audit rows, AGENTS.md data table.
7. Decision record: "NFL play, snap and roster-status data from 2022,
   season-spliced, full pbp columns".
8. Publish before merging (track-mode CI needs the new parquet).

### Weekly current season, past seasons once

- **Weekly:** `data-current.yaml` (Sundays 13:17 UTC, Aug to Jan, plus
  Feb 8, Mar 10, May 2) runs with `current`. For the NFL sources that is the
  current NFL season: ~25 MB downloaded, 0 CFBD calls, the whole season
  replaced, which also picks up nflverse's nightly corrections. The Mar 10
  run still counts 2026 as current, so it captures the playoffs and Super
  Bowl. No schedule change needed.
- **Once:** `Rscript data-raw/refresh-nfl.R 2022:2025 --yes --publish`.
  The script sets `CFB2NFL_REFRESH=true` and the selector, invalidates and
  builds **only** the NFL `raw_*`/`*_file` targets
  (`tar_make(names = ...)`), then rebuilds `duckdb_file` in track mode so
  every other table is read from its published parquet rather than
  re-ingested (`*_file` targets are `cue = "always"`, so building the
  DuckDB in refresh mode would re-run every source). With `--publish` it
  uploads the changed parquet and the DuckDB. After that, past seasons
  change only on a deliberate re-pull (for example, after an nflfastR EPA
  model update).
- Participation for 2026 enters through the weekly run automatically once
  nflverse publishes it.

## 6. Feature card

To move into `product/features.md` once the registry is on `main`: add the
row
`| F22 | NFL play, snap and roster-status data, 2022 on | G4, G1, G5 | P2, P1 | accepted | plans/nfl-pbp.md; enables F19 |`,
move the `Next free ID` comment to F23, and relink F19's row to "builds on
F22" (it currently links this plan).

### F22 · NFL play, snap and roster-status data, 2022 on

- **Goals:** G4 (primary), G1 (via F19: VISION §1 "what drafted players do
  in the NFL"), G5
- **Personas:** P2. Can query, for any drafted or UDFA player who reached
  the NFL in 2022 or later, every play they were credited on, every snap
  they played, and their roster status each week. P1 benefits through the
  F19 posts this enables.
- **Why now:** current NFL outcomes are roster seasons and box-score totals,
  which say nothing about linemen, playing time, or whether a pick started
  right away, had to earn it, or was hurt. Each table serves an F19
  question:
  - `nfl_rosters_weekly`: where a player stood each week (active, practice
    squad, inactive, injured reserve, cut, moved teams).
  - `nfl_snap_counts`: how much a player was on the field each game, every
    position and the current season included.
  - `nfl_pbp`: what a player's credited plays were worth (EPA, success),
    the basis for attributing contributions to game outcomes. All columns
    are kept because that attribution method is still open (user decision,
    2026-11-22).
  - `nfl_participation`: on-field presence per play for players with no
    credited plays (linemen), plus formation and personnel context.
- **Acceptance criteria:**
  - [ ] `nfl_pbp`, `nfl_participation`, `nfl_snap_counts` and
    `nfl_rosters_weekly` are published on `data-latest` and in the DuckDB,
    covering 2022 through the last completed NFL season (participation:
    through the last season nflverse published).
  - [ ] Of `outcomes` players with an NFL entry season of 2022 or later, at
    least X% appear in `nfl_rosters_weekly`, and at least Y% of
    `nfl_snap_counts` rows map to a `gsis_id`; the contract fails below
    these thresholds (X and Y set from the first backfill).
  - [ ] A contract or test fails the build if any of the four NFL tables is
    an upstream dependency of a model-input target (leakage, decision
    0014, G2 signals).
  - [ ] A `data-current.yaml` run replaces only the current NFL season's
    rows in the four tables, logs 0 CFBD calls for the NFL sources in
    `CFB2NFL_CALL_LOG`, and leaves the 2022 to 2025 row counts unchanged.
  - [ ] `cfb2nfl.duckdb` stays under the 2 GiB asset limit and `site.yaml`
    succeeds with the larger download.
  - [ ] `inst/dict` and `inst/data-model.md` give each table's grain, key
    and join path, say that season-grain `nfl_rosters` remains the
    longevity source, and include a worked query from `outcomes` to one
    named player's weekly status and snaps.
- **Out of scope:** any performance metric or thrive/fizzle classification
  (F19); injury reports and the trades table; NFL seasons before 2022; CFB
  `play_stats` backfill.
- **Cost:** 0 CFBD calls; ~190 MB added to `cfb2nfl.duckdb` (~560 MB total,
  ~21 years of headroom to the 2 GiB asset limit); four new tables; one
  decision record; new `data-raw/refresh-nfl.R`.
- **Tasks:** plans/nfl-pbp.md
- **Review:** feature-reviewer 2026-11-22: aligned after changes (findings
  2 to 7 applied; finding 1 resolved by option (b), per-table Why-now lines,
  since the user chose full pbp and participation)

## 7. Order of work

1. F22 card reviewed (`feature-reviewer`), tasks reviewed (`task-reviewer`).
2. Branch `data/nfl-pbp` from `main`; TDD the ingest/clean functions on
   fixtures, then the contracts.
3. `data-raw/refresh-nfl.R`; run the backfill locally, publish.
4. NEWS, decision record, PR; `task-reviewer` on the diff.
