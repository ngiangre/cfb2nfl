# 0047 — Team geography from the home stadium, mapped on the Teams tab

- **Status:** Accepted
- **Date:** 2026-11-14

## Context

Issue #48 asks where teams and conferences sit on a map. `teams.parquet` had
no coordinates, but the `/teams` response we already pull carries each
program's home venue (`location`: name, city, state, latitude, longitude,
capacity, ...), which `ingest_teams()` dropped. The Explorer plan
(`plans/explorer.md`, decision 0046) reserved a Map tab for this; on review
the map belongs on the Teams tab instead, as the way into a team's
conference.

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
- **The map lives on the Teams tab**, not a tab of its own, and highlights
  the selected team's conference that season (blue, everyone else grey, the
  team in its own color with a black ring) instead of a color per
  conference. FBS alone has 11 conference lineages plus independents, and a
  scatter can only keep about three categorical hues apart for color-blind
  readers. The conference chart's team chips below it mean identity never
  rests on color alone. The coordinates ride in `teams.json` (first view,
  ~15 KB gzipped with them) rather than a separate asset.
- A conference-spread measure (mean distance between members' stadiums) was
  built and dropped: it was not needed to read the map.
- **The basemap** is the `us-atlas` states TopoJSON with `topojson-client`,
  both from jsDelivr like hyparquet, drawn with Plot's `albers-usa`
  projection (Alaska and Hawaii insets). No R spatial packages are needed.

## Hypotheses / expectations

- Realignment is visible by stepping the season: the Big Ten's blue reaches
  the West Coast in 2024 (USC, UCLA, Oregon, Washington).
- Home-stadium coordinates are stable, so the weekly refresh rarely changes
  them.

## Consequences

- `teams.parquet` changed schema, so it had to be republished to
  `data-latest` before merging.
- A program that plays in a pro stadium off campus is placed at that
  stadium, not at the campus.
- The map depends on two CDN files. If they fail, the map shows the same
  Retry card as the other panels and the rest of the tab keeps working.

## Outcome / what we learned

_Filled in later._
