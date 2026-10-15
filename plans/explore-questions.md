# Plan: Explore — question-driven revision

Working plan (not a decision record; decisions land in `decisions/` once
ratified). Revised across sessions as sections get built. Feeds
`vignettes/explore.qmd`.

## Goal

Restructure `vignettes/explore.qmd` from "chart families" (time series / 2D /
3D exemplars) into **questions**: each gets an answer, a viz, and a caveats
callout. Keep existing exemplars/dossiers, regrouped where they serve a
question.

## Question-by-question feasibility

| # | Question | Answerable? | Approach |
|---|----------|-------------|----------|
| 1 | Made the NFL draft / didn't | Yes | `link_drafted()` flags drafted among the model population (players with a stat line in draft-eligible seasons). State the denominator caveat — only players appearing in `player_stats`/`roster` are measurable, not "all college players". |
| 2 | Entered draft but not selected | No, not directly | CFBD `/draft/picks` lists only *selected* players. Proxy: final eligible season with no pick row (conflates returning to school with declaring-undrafted). Label as proxy. |
| 3 | Career-ending injuries | No injury data | CFBD has no injury feed. Proxy: career ends mid-eligibility (missing seasons while `class_year` says eligible) without NFL outcome. Present as an *injury-shaped gap* analysis. |
| 4 | College career length | Yes | Distinct seasons per `playerId` in `roster` (full backbone — includes no-stat seasons). |
| 5 | Transfers: how many, when | Yes | `add_change_features()` already derives team changes + tier direction. Viz: counts by season, direction (up/down/lateral) over time, share of careers with ≥1 transfer. |
| 6 | Performance arc + opponent quality | Partially | Arcs: per-player stat trajectory by season index (pivot long stats). Opponent adjustment: only season-level team strength exists (SRS / SP+ in `coaches.parquet`) — contextualize the player's team strength per season, not per-game opponents. Per-game opponent quality needs a `/games` ingest (new target). |
| 7 | Teams/conferences spatially | Needs new ingest | `teams.parquet` has no coordinates. Add ingest for venue lat/lon (CFBD venues), then a `leaflet`/`plotly` map colored by conference. |
| 8 | Position stability HS→college→NFL | Yes | Chain `recruiting.recruit_position` → `roster.position` → NFL `position` (slot-bridged picks), restricted to name-guarded linked players. Transition matrix / alluvial. |
| 9 | Drafts by college × position | Yes | `picks` alone: count by `collegeTeam` × `position`. Extends `viz_drafts_by_team`. |
| 10 | Playing time per game / season | Partially | Season stats include games-played-style stats (check `stat_taxonomy` coverage); usage proxies = touches/attempts per game from season totals. True per-game/snap data needs a `/games` or player-game stats ingest. |
| 11 | Injured vs. benched | Not distinguishable | Season-grain data can't separate them; CFBD injury designations out of scope. Explicit limitation. |
| 12 | Define redshirts | Yes, approximately | Two signals: `class_year` (1–5) vs. observed seasons (5th-year player); roster presence with no stat line (redshirt-season proxy). Formalize with documented rules + caveats. |

## Proposed explore.qmd structure

1. **Draft population** — made it / didn't; draft-eligible denominator note.
2. **Career shape** — length distribution, redshirt definitions, performance arcs.
3. **Movement** — transfers, HS→college→NFL position flows, spatial map.
4. **Production context** — drafts by school × position, opponent-quality-adjusted arcs.
5. **What the data cannot say** — injuries, entered-but-not-selected, injured-vs-benched. Honest limitations section.

## Shared R functions to create

- [x] `career_summary(roster)` — seasons played, first/last season, gap
  seasons, transfer count (roster backbone grain). Feeds questions 1, 4, 5, 12.
  Now a pipeline target (`career`) bundled in the DuckDB (decision 0021).
- [x] `flag_redshirt(roster, player_stats)` — redshirt logic in one tested
  place (stat-gap rule + fifth-year signal). Pipeline target `roster_flags`
  (decision 0021).
- [ ] `season_arc(player_stats, stat_pair)` — pivot one stat to a per-player
  per-season arc for plotting (question 6).
- [x] **Shared ggplot theme + team-color scale in `R/viz.R`** —
  `theme_cfbstats()`, `team_color_values()`, `scale_fill_team()`,
  `scale_color_team()`.
- [ ] New ingest: venue lat/lon table (dict + DuckDB bundle entry +
  `inst/data-model.md`, per decisions 0017/0018). NOTE: this is an *ingested*
  table, so unlike the derived tables of decision 0021 it must be published to
  the `data-latest` release before merge (constraint below).

## New contracts

- [x] Redshirt-rule sanity (`contract_redshirt()`).
- [x] Career-length bounds, ≤ ~7 seasons (`contract_career_summary()`).
- [x] Transfer-count bounds (inside `contract_career_summary()`).

## Release/CI constraint

Any new **ingested** table must be published to the `data-latest` release
before merge, or track-mode CI/site build breaks (see AGENTS.md gotchas).
**Derived** tables (built from other cleaned tables, per decision 0021) do NOT
need publication — they ship in the DuckDB bundle + dict and rebuild in any
mode.

## Status

- [x] Viz theme + team-color scale (`R/viz.R`) — `theme_cfbstats()`,
  `team_color_values()`, `scale_fill_team()`, `scale_color_team()`.
- [x] `career_summary()` + career-length section
- [x] Transfers section — `transfer_counts()`, `transfer_rate()`,
  `viz_transfers_by_season()`; explore.qmd "Movement" section.
- [x] Redshirt definition + section — `flag_redshirt()` (stat-gap + fifth-year
  signals), `contract_redshirt()`, `viz_redshirt_by_career_length()` +
  `viz_redshirt_seasonality()` exposing the stat-coverage confound.
- [x] Derived feature tables in the pipeline (decision 0021) — `career`,
  `roster_flags`, `ps_change` as contracted targets with audit rows; bundled
  into the 14-table `cfbstats.duckdb` with dicts + ERD entries;
  `player_dossier()` gains a Career & eligibility section; `explore.qmd` reads
  the targets instead of recomputing.
- [ ] Performance arcs (+ opponent-quality context). Design constraint
  (question 6): arcs come from pivoting the long `player_stats`; opponent
  adjustment is season-level only (SRS / SP+ already on `ps_change` via the
  coach link) — per-game opponent quality needs a `/games` ingest, out of
  scope for v1. Build as a derived table target under the decision-0021 recipe
  (function + contract + dict + DuckDB + ERD + reader-facing section).
- [ ] Position-flow (HS→college→NFL) — name-guarded chain
  `recruiting.recruit_position` → `roster.position` → slot-bridged NFL
  position; transition matrix / alluvial.
- [ ] Drafts by school × position — `picks` alone; extends
  `viz_drafts_by_team`.
- [ ] Venues ingest + spatial map — needs the ingested venues table published
  to `data-latest` BEFORE merge (release/CI constraint above).
- [ ] Limitations section (injuries, entered-not-selected, injured-vs-benched).
- [ ] Restructure explore.qmd into the question sections above.
