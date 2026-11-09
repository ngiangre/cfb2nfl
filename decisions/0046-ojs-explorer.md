# 0046 — OJS explorer: static assets, hyparquet range reads, plotly 3D

- **Status:** Accepted
- **Date:** 2026-11-08

## Context

Issue #70 replaces the Visualizations page with one explorer a fan can drill
through on a phone: conference → team → season → game → play, position →
player → NFL outcome, and combine measurables (spec: `plans/explorer.md`).
It has to make zero CFBD calls, update weekly from the refreshed tables, and
stay light enough on a phone. Decision 0006 made R htmlwidgets the default
and reserved Observable JS "for a few bespoke explorables where its
interactivity clearly wins". The explorer is that case: drill-down across
~160k player-seasons and 3.1M plays cannot be embedded in one widget, and
crosstalk, pre-generated per-team pages, and a Shiny app were weighed and
set aside in the 2026-11-08 design discussion (clunky on mobile, hundreds of
pages, and hosting, respectively).

A throwaway spike (`spike/explorer-ojs`, not merged) built one page inside the
altdoc site and measured it at a 390×844 viewport with Playwright (mouse
events, not real touch).

| Question | Measured |
|---|---|
| OJS cells run in the altdoc-rendered site | Yes, no console errors |
| `resources: explorer-data/**` ships runtime-fetched files to `docs/` | Yes, all 19 files |
| First-view data (`team_season.json` + `combine.json`) | 1.86 MB raw, **175 KB gzipped** (Pages gzips JSON) |
| DuckDB-WASM (eh bundle) | wasm 35.7 MB raw / **7.0 MB gz** + worker 185 KB gz |
| DuckDB-WASM one-game read from `plays_2025.parquet` (13.5 MB, 59 row groups) | 8 range requests, 0.5 MB, 37–645 ms |
| **hyparquet** module | 68 KB raw / **21 KB gz** |
| hyparquet one-game read, row groups pruned by `gameId` min/max | footer (512 KB) + one row group (~200–240 KB), **20–29 ms**, rows match DuckDB |
| Per-team-season JSON fallback for plays | 311 files, 398 MB for one season |
| plotly gl3d partial bundle | 1.7 MB raw / **533 KB gz**; drag rotates |
| Frozen page (`freeze = TRUE`) picks up regenerated assets | Yes, the default season moved without touching the `.qmd` |
| URL hash round-trip (`#season=…&team=…`) | Read on load and rewritten on change |

## Decision

- **Quarto OJS for the explorer page only.** Observable Plot and Inputs for
  2D charts and controls. Every other page stays on R htmlwidgets (0006
  otherwise stands).
- **Parquet with hyparquet, not DuckDB-WASM.** Large assets (plays, player-
  seasons per position group) are parquet. Plays ship as one file per game,
  `plays/<season>/<game_id>.parquet`, and the page fetches the whole file
  (`(await fetch(url)).arrayBuffer()`, then hyparquet reads the buffer). No
  range requests: GitHub Pages gzips `application/octet-stream` for browsers,
  which breaks them (see Outcome). DuckDB-WASM costs 330× more bytes for no
  gain at this access pattern. Per-team JSON is ruled out by size.
- **Small assets are JSON**, normalized: team name, color, and logo live once
  in `teams.json`, not on every `team_season` row (the spike's 1.1 MB
  `team_season.json` was mostly repeated strings).
- **plotly.js gl3d partial bundle** for the 3D combine scatter, loaded only
  when the Combine tab opens.
- **No `freeze: false`.** All data is fetched at runtime and the default
  season is computed in the browser from the data, so the frozen render stays
  correct when `site.yaml` regenerates the assets.
- **The URL hash carries every state key** (`tab`, `season`, `team`, `game`,
  `pos`, `player`). The page listens for `hashchange`, so editing the hash
  updates the view without a reload.

## Hypotheses / expectations

These are the budgets later steps hold to:
- First view ≤ 250 KB of gzipped data assets, with no parquet reader or 3D
  library loaded.
- Opening a game: one whole game file (median ~14 KB, max ~23 KB), under
  200 ms after the transfer.
- The Combine tab costs ≈ 550 KB gzipped once (plotly gl3d + its data).

## Consequences

- A second viz language on one page. Its logic stays thin: R builds every
  derived value (percentiles, elapsed time, labels) in tested `export_*`
  targets, and the JS only filters and draws.
- Runtime CDN dependencies (jsDelivr for hyparquet, the plotly CDN), pinned
  to major versions.
- The export writer has to write one file per game in game order, and a
  contract checks that the plays directory holds exactly one file per game
  (no missing or stray files).
- Defects seen in the spike that the real build must avoid: a cell that
  references a heavy library before its guard loads it eagerly; the hash
  writer dropped `game`; season numbers were formatted as "2,025"; a bare
  side-effect cell printed `undefined`.
- Real touch input (rotate, scrub) is still untested, so step 2 checks it on
  a physical phone.

## Outcome / what we learned

The spike's range reads passed on its local test server, which never
compresses. The live site broke them: GitHub Pages gzips
`application/octet-stream` responses when the client sends
`Accept-Encoding: gzip` (browsers always do, and `fetch` cannot turn it off).
HEAD reported the compressed length (12,634,270 bytes against 14,918,990
real), and range requests applied to the compressed stream, so the footer read
failed with "parquet file invalid (footer != PAR1)". **Range reads of parquet
do not work on GitHub Pages.**

The fix writes one parquet file per game and fetches it whole, with no footer
read and no per-file metadata cache. hyparquet stays as the reader. The build
produces 17,433 game files (median 13.8 KB, max 23.1 KB, 246 MB in total);
the total is larger than the ~129 MB of season files because each file
carries its own footer, and a game still costs one request. Checked at a
390×844 viewport against a server that gzips every response (as Pages does):
the Game section draws its two charts and a play card with no errors, and
switching games loads each game's file whole, about 15 KB on the wire.

**Per-game files were too many.** The 17,433 per-game files made
`actions/deploy-pages` time out (10 minutes) while Pages processed the
artifact, so the deploy failed. The plays now ship as shards:
`plays/<season>/<game_id % 100>.parquet`, at most 100 per season (about
1,700 in all, 100 to 250 KB each), each holding that season's games in the
shard in play order. The page still fetches a file whole (no range reads),
filters to the open game, and caches the parsed shard, so other games in it
load for free. The deploy step also sets `timeout: 1800000` as a margin, and
the plays-files contract caps a shard at 400 KB.
