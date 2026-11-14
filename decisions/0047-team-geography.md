# 0047 — Team geography from the home stadium, and the Explorer Map

- **Status:** Accepted
- **Date:** 2026-11-14

## Context

Issue #48 asks where teams and conferences sit on a map. `teams.parquet` had
no coordinates, but the `/teams` response we already pull carries each
program's home venue (`location`: name, city, state, latitude, longitude,
capacity, ...), which `ingest_teams()` dropped. The Explorer plan
(`plans/explorer.md`, decision 0046) reserved a Map tab for this.

## Decision

- **A team's location is its home stadium**, taken from `/teams` `location`
  at no extra API call. `teams` keeps `venue`, `city`, `state`, `latitude`,
  `longitude`; capacity, dome and the rest stay out until a question needs
  them. `GET /venues` (one call) remains the fallback for neutral sites.
- **The contract** requires coordinates inside a US bounding box (latitude
  18 to 72, longitude -170 to -60, so a swapped pair fails) and coordinates
  for every FBS program. Lower divisions are often missing a venue and are
  not held to coverage. `ok_teams` now gates every `contract_teams()` agent,
  not just the coverage one.
- **Conference spread** is the mean great-circle (haversine) distance over
  every pair of members' home stadiums, per season, with membership from the
  season's own games. Independents get no spread. It reads as "a typical trip
  between two members".
- **One conference is highlighted at a time** on the map (blue, everyone
  else grey, the selected team ringed in its own color) instead of a color
  per conference. FBS alone has 11 conference lineages plus independents, and
  a scatter can only keep about three categorical hues apart for
  color-blind readers. The member list under the map, as chips, means
  identity never rests on color alone.
- **The basemap** is the `us-atlas` states TopoJSON with `topojson-client`,
  both from jsDelivr like hyparquet, drawn with Plot's `albers-usa`
  projection (Alaska and Hawaii insets). No R spatial packages are needed.

## Hypotheses / expectations

- Realignment is visible as a jump in spread: the Big Ten roughly doubles in
  2024 (USC, UCLA, Oregon, Washington), the ACC follows with Stanford, Cal
  and SMU.
- Home-stadium coordinates are stable, so the weekly refresh rarely changes
  them.

## Consequences

- `teams.parquet` changed schema, so it had to be republished to
  `data-latest` before merging.
- A program that plays in a pro stadium off campus is placed at that
  stadium, not at the campus.
- The Map tab depends on two CDN files. If they fail, the tab shows the
  same Retry card as the others.

## Outcome / what we learned

_Filled in later._
