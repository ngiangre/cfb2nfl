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

<!-- Next free ID: F23 -->

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

### F19 · NFL thrive-or-fizzle from NFL play-by-play

- **Goals:** G4 · **Personas:** P1, P2 · **Status:** idea
- **Links:** `plans/nfl-pbp.md`
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
