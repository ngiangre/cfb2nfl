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

- `career_summary(player_season)` — seasons played, first/last season, gap
  seasons, transfer count. Feeds questions 1, 4, 5, 12.
- `flag_redshirt(player_season, roster)` — redshirt logic in one tested place.
- `season_arc(player_stats, stat_pair)` — pivot one stat to a per-player
  per-season arc for plotting.
- **Shared ggplot theme + team-color scale in `R/viz.R`** (existing flagged
  TODO — do first, every new figure needs it).
- New ingest: venue lat/lon table (dict + DuckDB bundle entry +
  `inst/data-model.md`, per decisions 0017/0018).

## New contracts

- Redshirt-rule sanity.
- Career-length bounds (≤ ~7 seasons).
- Transfer-count bounds.

## Release/CI constraint

Any new table must be published to the `data-latest` release before merge, or
track-mode CI/site build breaks (see AGENTS.md gotchas).

## Status

- [x] Viz theme + team-color scale (`R/viz.R`) — `theme_cfbstats()`,
  `team_color_values()`, `scale_fill_team()`, `scale_color_team()` already in
  place; `viz_career_length()` added on top of them.
- [x] `career_summary()` + career-length section
- [x] Transfers section — `transfer_counts()`, `transfer_rate()`,
  `viz_transfers_by_season()`; explore.qmd "Movement" section.
- [ ] Redshirt definition + section
- [ ] Performance arcs (+ opponent-quality context)
- [ ] Position-flow (HS→college→NFL)
- [ ] Drafts by school × position
- [ ] Venues ingest + spatial map
- [ ] Limitations section
- [ ] Restructure explore.qmd into question sections
