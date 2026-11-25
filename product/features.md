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

<!-- Next free ID: F25 -->

## G1 · Answer the project's questions with evidence

### F07 · Posts: who reaches the draft

- **Goals:** G1 · **Personas:** P1 · **Status:** shipped
- **Links:** posts 2026-10-24 (outcome prevalence, eligibility by position)
- **Tasks:**
<!-- tasks F07 -->
- [x] [#105](https://github.com/ngiangre/cfb2nfl/issues/105) Revise F07 posts for the roster population of outcomes
- [x] [PR #118](https://github.com/ngiangre/cfb2nfl/pull/118) docs(posts): revise outcome posts for the roster population; Explorer lists NFL entrants without a stat line
- [x] [PR #120](https://github.com/ngiangre/cfb2nfl/pull/120) docs(posts): revise the clock-dependent posts for the corrected eligibility clock (F07, F10, F11)
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
- [x] [#106](https://github.com/ngiangre/cfb2nfl/issues/106) Revise F09 posts for the roster population of outcomes
- [x] [PR #118](https://github.com/ngiangre/cfb2nfl/pull/118) docs(posts): revise outcome posts for the roster population; Explorer lists NFL entrants without a stat line
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
- [x] [#107](https://github.com/ngiangre/cfb2nfl/issues/107) Revise F10 posts for the roster population of outcomes
- [x] [PR #118](https://github.com/ngiangre/cfb2nfl/pull/118) docs(posts): revise outcome posts for the roster population; Explorer lists NFL entrants without a stat line
- [x] [PR #120](https://github.com/ngiangre/cfb2nfl/pull/120) docs(posts): revise the clock-dependent posts for the corrected eligibility clock (F07, F10, F11)
<!-- /tasks -->

### F11 · Post: combine invite-to-draft funnel

- **Goals:** G1 · **Personas:** P1 · **Status:** shipped
- **Links:** post 2026-11-14
- **Tasks:**
<!-- tasks F11 -->
- [x] [#64](https://github.com/ngiangre/cfb2nfl/issues/64) Blog post: combine measurables by position, and the invite-to-draft funnel
- [x] [#108](https://github.com/ngiangre/cfb2nfl/issues/108) Revise the combine funnel post for the roster population of outcomes
- [x] [PR #118](https://github.com/ngiangre/cfb2nfl/pull/118) docs(posts): revise outcome posts for the roster population; Explorer lists NFL entrants without a stat line
- [x] [PR #120](https://github.com/ngiangre/cfb2nfl/pull/120) docs(posts): revise the clock-dependent posts for the corrected eligibility clock (F07, F10, F11)
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
- [ ] [#68](https://github.com/ngiangre/cfb2nfl/issues/68) Measure play-stats revisions (Nov 15 to Dec 6 runs), record, then remove the measurement
- [ ] [#95](https://github.com/ngiangre/cfb2nfl/issues/95) data(play_stats): backfill 2025 and 2024 in December, 2023 in January
- [x] [PR #121](https://github.com/ngiangre/cfb2nfl/pull/121) docs(decisions): record the first play-stats re-pull counts, extend the measurement two weeks (F04)
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

### F24 · Post: how college careers end, by position, as competing outcomes over time

- **Goals:** G1 · **Personas:** P1 (P2 for method) · **Status:** shipped
- **Links:** posts 2026-10-24 (outcome prevalence, eligibility by
  position), extending F07; decision 0032 (`outcomes` survival bookkeeping)
- **Why:** reading the 2026-10-24 posts, the user asked whether, by
  position group, the NFL outcome is a time-to-event question with mutually
  exclusive events over time. Those posts report per-season rates, which
  answer "how often" but not "by when, and instead of what". Each eligible
  season a player is drafted, signs as an undrafted free agent, exhausts
  eligibility undrafted, or plays on; the first three are mutually
  exclusive and absorbing (a season off every roster followed by a return
  is a missed season, not an ending). P1 wants "of every 100 eligible
  linebackers, how many are drafted by their third eligible season, and
  what happened to the rest?". F17 later uses the hazards this post
  describes (the prevalence post's eligible-season-index followup).
- **Acceptance criteria** (revised 2026-11-25 to the post as written: three
  endings, left the data folded into eligibility ended undrafted, the
  recruiting-record comparison in place of the drafted-only curve and the
  three-treatment table, and the ruled-out entrants counted overall rather
  than by position group):
  - [x] A dated post shows, for each position group with at least 30
    players at risk (others named as omitted), the cumulative incidence of
    drafted and signed undrafted by eligible season, each with an interval,
    and every ending's share (eligibility ended undrafted included) at the
    third eligible season.
  - [x] At every eligible season, the cumulative incidences plus the share
    still playing sum to 100% (an `expect_equal` check in the tests).
  - [x] The post defines censoring (still playing, awaiting a first draft),
    takes each player's ending from his final eligible season (a missed
    season is not an ending), and fixes his group at his position in his
    first eligible season, in the nine groups of the 2026-10-24 eligibility
    post.
  - [x] The post reports how many NFL entrants are ruled out because the
    clock puts their entry before their first eligible season, and says in
    plain language why they are missing from the curves.
  - [x] The post shows, on one group, how each season's chance is computed
    from the players still at risk, and explains in plain language before
    naming Aalen-Johansen why that differs from a simple share.
  - [x] The post compares every NFL route for players with and without a
    matched recruiting record, the check on the estimated clock.
  - [x] A fan can hover any curve point and read the group, season, share,
    interval and players at risk; every number in the prose is an inline
    variable (the title states the finding as of the last revision).
  - [x] Named players show each ending, their paths computed from the data
    and linked to their Explorer page (offensive linemen unlinked), and the
    post says the curves describe groups, not any one player's chances.
  - [x] The functions that build the competing-risks frame and the curves
    are tested (`testthat`), including a fixture where the estimate
    matches a hand-computed Aalen-Johansen value.
- **Depends on:** the `outcomes` label fixes found 2026-11-22 (drafted
  players labeled `left_data` after a final season with no stat line, and
  labeled `signed_udfa` when the pick's id differs from the stat id);
  without them the drafted curves are understated, most for linemen.
- **Out of scope:** covariate models, cause-specific hazard regressions or
  forecasts (F17); NFL careers after entry (F19); a new published table
  (decision 0041: build on the fly from `outcomes`).
- **Cost:** 0 CFBD calls; no new tables; `survival::survfit()` multi-state
  (installed), optionally `tidycmprsk`/`ggsurvfit` in Suggests. Decision
  record: none (whether F17 treats a final season off every roster as an
  ending is F17's call).
- **Review:** feature-reviewer 2026-11-22: aligned after changes (8
  findings, all applied); 2026-11-25: criteria revised to the post as
  written, aligned after changes (all applied)
- **Tasks:**
<!-- tasks F24 -->
- [ ] [#97](https://github.com/ngiangre/cfb2nfl/issues/97) Post: how college careers end, by position, as competing outcomes over time (F24)
- [x] [PR #98](https://github.com/ngiangre/cfb2nfl/pull/98) docs(product): F24 competing-outcomes post card
- [x] [PR #101](https://github.com/ngiangre/cfb2nfl/pull/101) feat(post): how college careers end, by position, as competing outcomes (F24)
- [x] [#109](https://github.com/ngiangre/cfb2nfl/issues/109) Revise the career-endings post for the roster population of outcomes
- [x] [PR #115](https://github.com/ngiangre/cfb2nfl/pull/115) docs(post): career endings on the roster population; fix the site build (F24)
- [x] [PR #122](https://github.com/ngiangre/cfb2nfl/pull/122) docs(posts): build the career endings post up to its probabilities (F24)
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
- [x] [#110](https://github.com/ngiangre/cfb2nfl/issues/110) Explorer: player outcomes rebuilt on the roster population of outcomes
- [x] [PR #118](https://github.com/ngiangre/cfb2nfl/pull/118) docs(posts): revise outcome posts for the roster population; Explorer lists NFL entrants without a stat line
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
- [x] [PR #116](https://github.com/ngiangre/cfb2nfl/pull/116) ci(site): deploy Pages in a separate job
<!-- /tasks -->

### F18 · querychat companion app

- **Goals:** G3 · **Personas:** P1 · **Status:** deferred (2026-11-22, not
  for now)
- **Links:** VISION §7
- **Tasks:**
<!-- tasks F18 -->
<!-- /tasks -->

## G4 · Follow players into the NFL

### F22 · NFL outcome labels: draft-slot bridge, longevity, outcomes table over every roster player-season

- **Goals:** G4, G2, C1 · **Personas:** P1, P2 · **Status:** accepted
  (reopened 2026-11-24 for the roster population)
- **Links:** decisions 0014, 0032
- **Why:** the `outcomes` population is player-seasons with a stat line, so
  the denominator a fan reads ("how many players like him get drafted?")
  leaves out offensive linemen, every defender before 2016 (CFBD has no
  defensive stats until then) and final seasons without a stat line: 916 of
  4,095 picks from 2011 to 2026 have no stat line at all. Rosters are
  complete every season, so they define who could have been drafted.
- **Acceptance criteria:**
  - [x] Every roster player-season (reused ids and pre-enrollment seasons
    excluded, issue #114) appears exactly
    once in `outcomes`, each with `has_stat_line` and a season-aware tier;
    the contract fails on a missing tier rather than defaulting. Both
    columns and the tier source are defined in `inst/dict/outcomes.yml`
    and `inst/data-model.md`.
  - [x] Every 2011-2026 pick whose CFBD id is on a roster has a drafted row
    in `outcomes`, linemen and pre-2016 defenders included.
  - [x] No drafted row's `draft_year` differs from the pick's draft year
    (234 today; Kenyon Green, 2022 pick on his 2019 row, is a test case).
  - [ ] A pick whose name differs from the college name only by a nickname
    or spelling links to the player (Mitchell/Mitch Trubisky, Mo/Maurice
    Hurst, Obo/Ogbonnia Okoronkwo, Dawaune/Dawuane Smoot, Cam/Cameron
    Sutton as tests), and none is labeled undrafted.
  - [x] Every roster-only player who signed as an undrafted free agent
    (name guard, decision 0032) has `signed_udfa` on one entry row, and no
    drafted player's `gsis_id` is on an undrafted row.
  - [x] Rows past `last_complete_draft` have NA outcomes, never 0, for
    roster-only rows as for stat-line rows.
  - [x] `outcomes` carries each player's first roster season and a flag on
    the row that is that season (never NA, defined in
    `inst/dict/outcomes.yml`); flagged rows are kept, since 1.4% of picks
    enter the NFL right after their first roster season (transfers from
    programs the data does not cover).
  - [x] An imputed `hs_grad_year` is the earlier of the first roster and
    first stat season (decision 0051), flagged by `hs_year_imputed`.
  - [x] A decision record replaces the stat-line population (decision 0032
    and the v1 rule in AGENTS.md) with the roster population for both
    `outcomes` and the model population, and reports before/after row,
    player, eligible and drafted counts.
  - [x] Rebuilding and publishing `outcomes` makes 0 CFBD calls, shown by
    the call log.
- **Out of scope:** revising the posts that read `outcomes` (each owning
  post feature carries its own task); the forecast itself (F17). Explorer
  player outcomes rebuild from the new population with no code change; any
  Explorer page revision is an F13 task.
- **Cost:** 17 CFBD calls once, to re-pull the roster with names (#111);
  otherwise 0 CFBD calls, through a targeted refresh-mode build of
  `outcomes_file` alone (`tar_make(names = outcomes_file, shortcut = TRUE)`
  in a `data-raw/refresh-outcomes.R` like `refresh-nfl.R`) that refuses to
  publish if any CFBD call was made or another parquet changed. `outcomes`
  is written whole, not season-spliced, so no splice schema guard applies;
  the publish and merge happen in one sitting, Monday to Saturday. One
  decision record; schema change to a published table.
- **Review:** feature-reviewer 2026-11-24: aligned after changes (all
  applied)
- **Tasks:**
<!-- tasks F22 -->
- [x] [#99](https://github.com/ngiangre/cfb2nfl/issues/99) fix(outcomes): drafted and undrafted labels lost or misassigned (late entry, id mismatch, namesakes)
- [x] [PR #100](https://github.com/ngiangre/cfb2nfl/pull/100) fix(outcomes): keep late, id-mismatched and namesake NFL labels straight
- [x] [#102](https://github.com/ngiangre/cfb2nfl/issues/102) Outcomes population: roster player-seasons with a stat-line flag, not stat lines only
- [x] [#103](https://github.com/ngiangre/cfb2nfl/issues/103) fix(outcomes): pick name fallback misses nicknames and spellings (Trubisky labeled undrafted)
- [x] [#111](https://github.com/ngiangre/cfb2nfl/issues/111) fix(roster): keep CFBD roster names so roster-only players can match undrafted signings
- [x] [PR #112](https://github.com/ngiangre/cfb2nfl/pull/112) feat(outcomes): every roster player-season, with has_stat_line and tier (F22)
- [x] [PR #113](https://github.com/ngiangre/cfb2nfl/pull/113) fix(roster): keep CFBD names so roster-only players can be matched (F22)
- [x] [#114](https://github.com/ngiangre/cfb2nfl/issues/114) fix(roster): CFBD lists some players before they enrolled (Burrow at Ohio State in 2014)
- [x] [PR #117](https://github.com/ngiangre/cfb2nfl/pull/117) fix(outcomes): nickname pick links; model table on the roster population (F22, F17)
- [x] [PR #119](https://github.com/ngiangre/cfb2nfl/pull/119) fix(outcomes): the eligibility clock follows the NFL three-year rule for unrecruited players (F22)
- [x] [PR #123](https://github.com/ngiangre/cfb2nfl/pull/123) fix(roster): drop roster seasons listed before a matched recruiting class (F22)
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
- [x] [PR #96](https://github.com/ngiangre/cfb2nfl/pull/96) docs(product): tick F23 criteria 1 and 6; link #95 to F04
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
- [x] [#104](https://github.com/ngiangre/cfb2nfl/issues/104) Model population: roster player-seasons, matching outcomes
- [x] [PR #117](https://github.com/ngiangre/cfb2nfl/pull/117) fix(outcomes): nickname pick links; model table on the roster population (F22, F17)
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
