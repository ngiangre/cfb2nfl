# Features: what we build toward the goals

The middle of the chain **goal → feature → task** ([README.md](README.md)).
A feature is a capability a persona can use or rely on (a post series, an
explorer tab, a data asset, a model). Each one sits under its primary goal
or constraint ([goals.md](goals.md)) and names its persona(s)
([personas.md](personas.md)).

**Tasks are GitHub issues.** An issue (or PR) joins a feature with a line
`Feature: Fnn` in its body or a comment, and carries the label of each goal
or constraint on the feature's **Goals** line. The **Tasks** checklist on
every card is generated between its `<!-- tasks Fnn -->` markers by:

```sh
Rscript -e 'pkgload::load_all(quiet = TRUE); sync_feature_tasks()'
```

Do not edit inside the markers by hand; the next sync overwrites them.

Statuses: `idea` → `accepted` (passed the `feature-reviewer` agent) →
`in progress` → `shipped`, or `deferred` / `dropped` (say why). Features
shipped before 2026-11-22 were backfilled from the repo history and have no
acceptance criteria.

<!-- Next free ID: F24 -->

## G1 · Answer the project's questions with evidence

### F07 · Posts: who reaches the draft

- **Goals:** G1 · **Personas:** P1 · **Status:** shipped
- **Links:** posts 2026-10-24 (outcome prevalence, eligibility by position)
- **Tasks:**
<!-- tasks F07 -->
<!-- /tasks -->

### F08 · Posts: player movement

- **Goals:** G1 · **Personas:** P1 · **Status:** shipped
- **Links:** transfers, position stability, Buechele and Allen posts;
  decision 0036
- **Tasks:**
<!-- tasks F08 -->
- [x] [#49](https://github.com/ngiangre/cfb2nfl/issues/49) feat(analysis): position stability from high school to college to the NFL
<!-- /tasks -->

### F09 · Posts: coaches and programs

- **Goals:** G1 · **Personas:** P1 · **Status:** shipped
- **Links:** posts 2026-10-30, 2026-10-31 (counting coaches, conferences,
  who produces draftees, winning and draftees)
- **Tasks:**
<!-- tasks F09 -->
<!-- /tasks -->

### F10 · Posts: career shape

- **Goals:** G1 · **Personas:** P1 · **Status:** shipped
- **Links:** redshirt, performance arcs, playing time, absence posts;
  decisions 0037–0039, 0044
- **Tasks:**
<!-- tasks F10 -->
- [x] [#47](https://github.com/ngiangre/cfb2nfl/issues/47) feat(analysis): player performance arcs, adjusted for opponent strength
- [x] [#50](https://github.com/ngiangre/cfb2nfl/issues/50) feat(analysis): playing time per game and per season from game_player_stats
- [x] [#51](https://github.com/ngiangre/cfb2nfl/issues/51) feat(analysis): career-ending injury and injured-vs-benched proxies (data limits)
<!-- /tasks -->

### F11 · Post: combine invite-to-draft funnel

- **Goals:** G1 · **Personas:** P1 · **Status:** shipped
- **Links:** post 2026-11-14
- **Tasks:**
<!-- tasks F11 -->
- [x] [#64](https://github.com/ngiangre/cfb2nfl/issues/64) Blog post: combine measurables by position, and the invite-to-draft funnel
<!-- /tasks -->

### F12 · Post: game flow by EPA with play-level attribution

- **Goals:** G1, G3 · **Personas:** P1 · **Status:** shipped
- **Links:** post 2026-11-18
- **Tasks:**
<!-- tasks F12 -->
- [x] [PR #91](https://github.com/ngiangre/cfb2nfl/pull/91) feat(post): game-flow EPA post with play-level player attribution
<!-- /tasks -->

### F04 · Play-by-play and per-game play stats

- **Goals:** G1, C2 · **Personas:** P1, P2 · **Status:** shipped (backfill
  ongoing)
- **Links:** decisions 0031, 0045; `plans/plays.md`
- **Tasks:**
<!-- tasks F04 -->
- [x] [#44](https://github.com/ngiangre/cfb2nfl/issues/44) feat(data): ingest CFBD play-by-play into the pipeline, assets, and data model
- [ ] [#68](https://github.com/ngiangre/cfb2nfl/issues/68) Measure play-stats revisions (Nov 15 + Nov 22 runs), record, then remove the measurement
- [ ] [#95](https://github.com/ngiangre/cfb2nfl/issues/95) data(play_stats): backfill 2025 and 2024 in December, 2023 in January
<!-- /tasks -->

### F05 · Combine measurables linked to college players

- **Goals:** G1 · **Personas:** P1, P2 · **Status:** shipped
- **Links:** decision 0043
- **Tasks:**
<!-- tasks F05 -->
- [x] [#45](https://github.com/ngiangre/cfb2nfl/issues/45) feat(data): ingest nflverse combine data and link to CFBD athlete ids
<!-- /tasks -->

### F16 · Post style rules, checker and cold-read reviewer

- **Goals:** G1, C1 · **Personas:** P1, P2 · **Status:** shipped
- **Links:** decisions 0025, 0040; `R/post_style.R`
- **Tasks:**
<!-- tasks F16 -->
<!-- /tasks -->

### F21 · Question status board

- **Goals:** G1, G3 · **Personas:** P1 · **Status:** idea
- **Why:** P1 needs to see every question's status (answered, in progress,
  not answerable and why); today that lives in issue #11's triage comment
  and scattered `followups:`.
- **Tasks:**
<!-- tasks F21 -->
- [x] [#11](https://github.com/ngiangre/cfb2nfl/issues/11) Questions
<!-- /tasks -->

### F20 · Assistant-coach data feasibility post

- **Goals:** G1 · **Personas:** P1 · **Status:** idea
- **Links:** VISION §3
- **Tasks:**
<!-- tasks F20 -->
<!-- /tasks -->

## G3 · Let fans go from a question to an answer to the next question

### F13 · Interactive Explorer

- **Goals:** G3 · **Personas:** P1 · **Status:** shipped
- **Links:** decision 0046; `plans/explorer.md`
- **Tasks:**
<!-- tasks F13 -->
- [x] [#70](https://github.com/ngiangre/cfb2nfl/issues/70) feat(site): interactive explorer replacing the Visualizations page (teams, game timelines, players, combine, map)
- [x] [#78](https://github.com/ngiangre/cfb2nfl/issues/78) Explorer Suggestions
- [x] [#84](https://github.com/ngiangre/cfb2nfl/issues/84) Explorer Suggestions
- [x] [#87](https://github.com/ngiangre/cfb2nfl/issues/87) Show college and NFL jersey numbers alongside position on Explore pages
- [x] [#89](https://github.com/ngiangre/cfb2nfl/issues/89) Combine explorer: label UDFAs who made NFL rosters; clarify Draft pending
<!-- /tasks -->

### F06 · Team and conference geography

- **Goals:** G3 · **Personas:** P1 · **Status:** shipped
- **Links:** decision 0047
- **Tasks:**
<!-- tasks F06 -->
- [x] [#48](https://github.com/ngiangre/cfb2nfl/issues/48) feat(data): team and conference geography from /teams location (map)
<!-- /tasks -->

### F14 · Fan pages: Home, About, Explore hub, Blog index

- **Goals:** G3 · **Personas:** P1 · **Status:** shipped
- **Links:** decision 0006
- **Tasks:**
<!-- tasks F14 -->
<!-- /tasks -->

### F18 · querychat companion app

- **Goals:** G3 · **Personas:** P1 · **Status:** deferred (2026-11-22, not
  for now)
- **Links:** VISION §7
- **Tasks:**
<!-- tasks F18 -->
<!-- /tasks -->

## G4 · Follow players into the NFL

### F22 · NFL outcome labels: draft-slot bridge, longevity, outcomes table

- **Goals:** G4, G2 · **Personas:** P1, P2 · **Status:** shipped
- **Links:** decisions 0014, 0032
- **Tasks:**
<!-- tasks F22 -->
<!-- /tasks -->

### F23 · NFL play, snap and roster-status data, 2022 on

- **Goals:** G4, C1, C2 · **Personas:** P2 (P1 via F19) · **Status:** in progress
- **Why:** NFL outcomes today are roster seasons and box-score totals, which
  say nothing about linemen, playing time, or whether a pick played right
  away, had to earn it, or was hurt. Each table serves an F19 question:
  `nfl_rosters_weekly`, where a player stood each week (active, practice
  squad, inactive, injured reserve, cut, moved teams); `nfl_snap_counts`,
  how much he was on the field each game, every position and the current
  season included; `nfl_pbp`, what his credited plays were worth (EPA,
  success), the basis for attributing contributions to game outcomes, with
  all columns kept while that method is open (user decision 2026-11-22);
  `nfl_participation`, on-field presence per play for players with no
  credited plays (linemen), plus formation and personnel.
- **Acceptance criteria:**
  - [x] A P2 reader can download `nfl_pbp`, `nfl_participation`,
    `nfl_snap_counts` and `nfl_rosters_weekly` from `data-latest` and query
    them in the DuckDB, covering 2022 through the last completed NFL season
    (participation: through the last season nflverse published).
  - [x] Of `outcomes` players (drafted or undrafted) with an NFL entry
    season of 2022 or later, at least X% appear in `nfl_rosters_weekly`, and
    at least Y% of `nfl_snap_counts` rows map to a `gsis_id` (through a
    pipeline crosswalk target, not the explorer's); the contract fails below
    these thresholds, with X and Y set from the first backfill and recorded
    in the decision record and the contract.
  - [x] A test fails if any of the four tables is upstream of `model_table`
    or `model_fit` in `tar_network()` (NFL data stays an outcome, decision
    0014).
  - [x] The one-time `Rscript data-raw/refresh-nfl.R --yes` backfill (2022
    to current) with `CFB2NFL_CALL_LOG` set logs 0 CFBD calls, and every
    non-NFL parquet is unchanged afterwards.
  - [ ] A `data-current.yaml` run replaces only the current NFL season's
    rows in the four tables with 0 CFBD calls for them, and leaves the 2022
    to 2025 row counts unchanged.
  - [x] `cfb2nfl.duckdb` stays under the 2 GiB asset limit and `site.yaml`
    succeeds with the larger download.
  - [x] `inst/dict` and `inst/data-model.md` give each table's grain, key and
    join path, say that season-grain `nfl_rosters` remains the longevity
    source, state that coverage starts in 2022 (careers that began earlier
    are truncated; use season-grain `nfl_rosters` for whole careers) and
    that the current season is partial, and include a worked query from
    `outcomes` to one named player's weekly status and snaps.
- **Out of scope:** any performance metric or thrive/fizzle classification
  (F19); injury reports and the trades table; NFL seasons before 2022; CFB
  `play_stats` backfill.
- **Cost:** 0 CFBD calls; ~168 MB added to `cfb2nfl.duckdb` (535.8 MB
  measured after the backfill, ~21 years of headroom to the 2 GiB limit);
  four new tables; one decision record; new `data-raw/refresh-nfl.R`.
  Plan: `plans/nfl-pbp.md`.
- **Review:** feature-reviewer 2026-11-22: aligned after changes (2
  required + 4 optional findings, all applied)
- **Tasks:**
<!-- tasks F23 -->
- [ ] [#93](https://github.com/ngiangre/cfb2nfl/issues/93) feat(data): NFL play, snap and roster-status data, 2022 on (F23)
- [x] [PR #94](https://github.com/ngiangre/cfb2nfl/pull/94) feat(data): NFL play, snap and roster-status data from 2022 (F23)
<!-- /tasks -->

### F19 · NFL thrive-or-fizzle from NFL play-by-play

- **Goals:** G4 · **Personas:** P1, P2 · **Status:** idea
- **Links:** builds on F23
- **Tasks:**
<!-- tasks F19 -->
<!-- /tasks -->

## G2 · Forecast draft outcomes honestly

### F17 · Per-position draft forecast (explanatory and predictive)

- **Goals:** G2 · **Personas:** P1, P2 · **Status:** idea
- **Links:** VISION §5, §6; `R/model.R` is a placeholder
- **Tasks:**
<!-- tasks F17 -->
<!-- /tasks -->

## C1 · Every number is trustworthy and reproducible

### F01 · Cleaned parquet + DuckDB assets on the `data-latest` release

- **Goals:** C1 · **Personas:** P2 · **Status:** shipped
- **Links:** decisions 0016–0018
- **Tasks:**
<!-- tasks F01 -->
- [x] [#4](https://github.com/ngiangre/cfb2nfl/issues/4) Get data
<!-- /tasks -->

### F02 · Contract-gated pipeline with an audit log

- **Goals:** C1 · **Personas:** P2 · **Status:** shipped
- **Links:** decisions 0005, 0023
- **Tasks:**
<!-- tasks F02 -->
<!-- /tasks -->

### F15 · Technical pages: Data, Pipeline, Reference

- **Goals:** C1 · **Personas:** P2 · **Status:** shipped
- **Links:** decisions 0006, 0042
- **Tasks:**
<!-- tasks F15 -->
<!-- /tasks -->

## C2 · Stay current within the API budget

### F03 · Season-scoped scheduled refresh

- **Goals:** C2 · **Personas:** P1, P2 · **Status:** shipped
- **Links:** decision 0034
- **Tasks:**
<!-- tasks F03 -->
- [x] [#46](https://github.com/ngiangre/cfb2nfl/issues/46) feat(pipeline): season-scoped refresh (current season on a schedule, history on demand)
<!-- /tasks -->
