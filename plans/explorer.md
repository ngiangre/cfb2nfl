# Spec: interactive explorer (issue #70)

Status: design approved 2026-11-08; implementation not started. Replaces
`vignettes/visualizations.qmd` with one Quarto OJS page a fan can drill
through on a phone: conference → team → season → game → play, and
position → player → NFL outcome, plus combine measurables.

## Goals and non-goals

- **Goal:** a reader opens the page, sees a landscape for the season in progress
  (refreshed weekly), and keeps tapping deeper without losing their place. It works on a
  phone as well as on a desktop.
- **Goal:** zero CFBD calls. Everything is built in track mode from the
  published tables during `site.yaml`.
- **Non-goal:** per-play win probability (`/metrics/wp` is one call per game,
  ~1,700 a season). The game timeline uses score margin and cumulative PPA.
- **Non-goal:** polls, CFP seeds, SP+/FPI. Team rating is Elo only.
- **Non-goal:** offensive linemen in the stat views (they have no box-score
  stats). They still appear in team and outcome data.
- **Non-goal:** redshirts (dropped from the page).

## Defaults and global state

| State | Default | Notes |
|---|---|---|
| season | the in-progress season: the max `season` with a completed game in `games` (2026 as of 2026-11-08) | Selector covers 2010 to that season. It moves forward on its own as the weekly refresh ingests new games |
| team | Texas (`team_id` 251) | The hash and every explorer asset key teams by CFBD `team_id` (`teams.team_id` == `games.homeId`/`awayId`). Tables keyed by school name (`roster`, `player_stats`) are mapped to `team_id` in the export step |
| position group | Quarterback | From `position_group()` (`R/teams.R`); OL excluded |
| player | none | Set by tapping a dot or by search |
| tab | Teams | Map is added last |

All state lives in the URL hash, keyed by ids (team, game, player) rather
than names: `#tab=teams&season=2026&team=251&game=<gameId>&pos=QB&player=<athleteId>`.
It is read on load and written on change, so any view can be shared as a link
and the back button works. Selection is shared across tabs: picking a player in
a game timeline opens Players with that player highlighted.

## Weekly freshness

The plots update every week with no source edit. `data-current.yaml`
(Sundays in season) publishes the refreshed tables and dispatches
`site.yaml`. The site's `tar_make()` rebuilds the `export_*` assets from them,
and the page fetches those assets at runtime. Two things keep the page from
serving stale data:

- `explorer.qmd` sets `freeze: false`. Under the site's `freeze: auto`, a page
  whose source hasn't changed serves its cached render, so the default season
  and any knit-time numbers would stop moving.
- The `export_*` targets depend on the cleaned table targets, so any refresh
  that changes a table rebuilds its assets. A contract checks that the default
  season in the assets equals the max `season` with a completed game.

## Methods and data sources on the page

- **Equations in the margin.** Each formula a visual relies on is written out
  (KaTeX) in a margin note (`.column-margin`) beside that visual: elapsed game
  time, cumulative PPA, Elo expected win probability, percentile rank and its
  qualifiers. On narrow screens Quarto folds margin content inline, so this
  works on mobile too.
- **Data sources for each visual.** Each visual carries a "Data:" line naming
  the tables it is built from, each a link to that table's entry on the Data
  page (`data.html#table-<name>`). The shell step adds a per-table anchor to
  `vignettes/data.qmd`. Sources:

| Visual | Tables |
|---|---|
| Teams landscape, team view | `games`, `teams`, `conference_tiers` |
| Team-season strip | `games`, `teams` |
| Game timeline | `plays`, `play_types`, `games`, `play_stats` (player chips) |
| Players beeswarm, career | `player_stats`, `roster`, `teams`, `conference_tiers`, `outcomes`, `picks` |
| Combine 3D | `combine`, `outcomes`, `picks` |
| Draft & careers | as in the current charts (`picks`, `nfl_draft_picks`, `nfl_rosters`, `roster`) |
| Map | `teams` (location, #48), `games` |

## Page layout

One page, a sticky header (season selector + tab bar), then the active tab.
Each tab's data loads the first time the tab opens.

### Tab 1: Teams

1. **Landscape.** Small multiples, one per conference (membership as of the
   selected season; FBS by default, FCS behind a toggle). Each panel shows
   end-of-season Elo lines for its teams across 2010 to now, with the selected
   season marked by a vertical rule. Tapping a panel highlights its teams;
   tapping a line opens the team.
2. **Team view.** End-of-season Elo across seasons (line, team color) above
   a W-L bar per season. Tapping a season opens the team-season.
3. **Team-season view.** A strip of games by week: one tile per game showing
   W/L color, score, opponent logo, home/away/neutral, and the Elo change
   (`postgameElo - pregameElo`). A mini Elo line for the season sits above
   the strip. Tapping a tile opens the game.
4. **Game timeline** (games with `plays` rows):
   - x = elapsed game time,
     `(period - 1) * 900 + (900 - (clock_minutes * 60 + clock_seconds))`.
     Overtime periods extend past 3,600 without a clock.
   - Score margin from the selected team's side (step line), and cumulative
     PPA: the team's offensive `ppa` minus the opponent's, summed in play
     order (line).
   - Start annotation: pregame expected win probability from the Elo gap,
     `1 / (1 + 10^(-(elo_team - elo_opp) / 400))`. End annotation: CFBD's
     `postgameWinProbability` from `games`.
   - Markers on scoring plays and turnovers (by `playType`).
   - A crosshair (drag on touch, hover on desktop) shows a play card: quarter,
     clock, down & distance, yard line, score, and `playText`.
   - Beside the timeline, the season Elo line with this game highlighted, so a
     moment in the game reads against the team's trend.
   - Where `play_stats` rows exist (2026 on, past seasons when backfilled),
     the play card lists the players involved as chips that link to Players.
   - Games without plays show the tile summary and the line "No play-by-play
     for this game".

### Tab 2: Players

1. **Landscape.** A beeswarm for the selected position group and season: one
   dot per player with a stat line in the stat's category. The stat is
   selectable and defaults to the first in the table below. Dots are colored
   by outcome. The selected player is drawn larger with a team-color outline
   and a label. Filters: conference tier (Power + G5 by default, FCS
   optional). Search by name or school opens the player.
2. **Player career.** For each season, the player's percentile on each of the
   position's headline stats (lines, 0–100), with the team logo above each
   season so a transfer shows as a logo change. It ends with an outcome chip:
   *Drafted R1 #12 (Team)*, *Signed UDFA*, *No NFL*, or *Still playing*.

Headline stats (`player_stats` category/statType). Rate stats need a minimum
volume, so low-volume players don't sit at the 100th percentile:

| Position group | Stats (first = default) | Qualifier for rate stats |
|---|---|---|
| Quarterback | passing YDS, TD, INT, YPA, PCT; rushing YDS | YPA/PCT: ATT ≥ 100 |
| Running back | rushing YDS, TD, YPC; receiving YDS | YPC: CAR ≥ 50 |
| Receiver | receiving YDS, REC, TD, YPR | YPR: REC ≥ 15 |
| Tight end | receiving YDS, REC, TD, YPR | YPR: REC ≥ 10 |
| Defensive line | defensive SACKS, TFL, QB HUR, TOT | — |
| Linebacker | defensive TOT, TFL, SACKS, PD | — |
| Defensive back | defensive PD, interceptions INT, defensive TOT | — |
| Special teams | kicking FGM, PCT; punting YPP | PCT: FGA ≥ 10; YPP: NO ≥ 20 |

Percentile = `percent_rank()` within position group × season among
qualifying players (INT for QBs is reversed so a higher percentile is better).
The position comes from that season's roster row, falling back to the
player's nearest roster season. Outcome categories come from
`career_end_status()` / `outcomes` (drafted by round group, signed UDFA,
no NFL, still playing), with reader-facing labels.

### Tab 3: Combine

- A 3D scatter is always shown. Axes default to height × weight × 40-yard
  dash; each axis is selectable from height, weight, 40, vertical, broad
  jump, bench, shuttle, 3-cone.
- Points are colored by draft outcome (round group / undrafted) and filtered
  by position group (default Quarterback) and combine season range. Tapping a
  point opens the player when `athlete_id` is linked. `link_method ==
  "unmatched"` points show their name with no link.
- Touch rotate/zoom plus a "reset view" button. Combine data is pre-draft and
  shown as a description only; it is not a model input.
- Shares its `build_*()` function with the #64 combine post.

### Tab 4: Draft & careers

This tab holds the old page's draft time series, NFL longevity, and transfers.
Each chart moves as is or is cut where a dated post already covers it.

### Tab 5: Map (ships last)

Teams on a US map (AK/HI insets) for the selected season: dot size = wins,
color/shape = conference. Tapping a team opens Teams → team view. Blocked on
#48 publishing team locations.

## Data assets

New `export_*` targets in `_targets.R` (track mode, downstream of the cleaned
tables) write static files to `vignettes/explorer-data/`, which the page
fetches at runtime. A `build_explorer_*()` function in `R/explorer.R` backs
each asset, tested on fixtures. These assets are not added to the DuckDB
(decision 0041).

| Asset | Grain | Est. size | Loaded |
|---|---|---|---|
| `teams.json` | team (name, conference by season, colors, logo) | ~50 KB | first view |
| `team_season.json` | team × season: end Elo, W, L, conference, tier | ~4.5k rows, ~150 KB | first view |
| `games_<season>.json` | game: teams, points, pre/post Elo, postgame WP, week | ~1–2k rows/season | on team-season open |
| `plays_<season>.parquet` | play, slim columns, sorted by `gameId` | 3.1M rows total | on game open |
| `player_season_<pos>.parquet` | player × season: stats, percentiles, team, tier | ~160k rows total, split by group | on Players open |
| `player_outcome.json` | player: outcome chip fields | ~70k rows | on Players open |
| `combine.json` | combine invitee: measurables, outcome, `athlete_id` | ~5.7k rows | on Combine open |

Budget: first view (`teams.json` + `team_season.json`) ≤ 1 MB transferred.
The heavy files (plays, player-season) are parquet read with DuckDB-WASM
HTTP range requests, so a game open fetches only that game's row groups.
DuckDB-WASM itself (several MB) loads only on the first game or Players
open. The spike (step 1) confirms this or falls back to per-team-season JSON
chunks. GitHub Pages limits: 1 GB site, 100 MB per file. The total must stay
well under both.

## Front end

- Quarto OJS cells inside `vignettes/explorer.qmd` (altdoc copies it like any
  vignette). Observable Plot for 2D, Observable Inputs for controls,
  DuckDB-WASM for parquet, and plotly.js (via `require`) for the 3D scatter.
  If the spike finds plotly too heavy, the alternative is a three.js-based
  scatter; the spike decides.
- Team colors/logos come from `teams.json`, which the export target builds
  through `team_color_values()` (`R/viz.R`), so the R and JS palettes match.
- Mobile: single column under 600px, tap targets ≥ 44px, every tooltip also
  opens on tap, no hover-only information, large type (match
  `theme_cfb2nfl(base_size = 16)`), and swarms/strips that scroll horizontally
  instead of shrinking.
- Reader-facing labels everywhere (position groups, outcome names, stat names
  like "Passing yards"), mapped in R and shipped in the assets.
- The setup chunk follows the vignette convention (visible code, output
  suppressed). The page is not a dated post, so `check_post_style()` and the
  vignette-reviewer don't apply. The fan-experience-improver skill reviews it.

## Errors and edge cases

- An asset fetch failure shows an inline "Couldn't load <thing>, retry" card
  in that panel. The rest of the page keeps working.
- An unknown hash value (team renamed, bad id) falls back to the default for
  that key and drops it from the hash.
- A season with no completed games yet (preseason, before week 0) falls back
  to the latest season that has one.
- A player with no qualifying stats in a season leaves a gap in the career
  line (no zero).
- A combine point with no link shows the name only.
- The 2020 COVID season has fewer games: no special handling, the tiles
  just show fewer games.

## Testing and contracts

- **testthat** for every `build_explorer_*()`: elapsed-time math (incl. OT),
  cumulative PPA sign by side, Elo expectation formula, percentile direction
  (INT reversed), rate-stat qualifiers, OL exclusion, outcome labels, default
  season rule.
- **pointblank contracts** (`contract_explorer_*()`, wired into
  `contract_gate`): row counts match sources (no silent join loss), e.g.
  `team_season` rows == distinct team × season in completed `games`; percentiles
  in [0, 1]; every team in `team_season` has a color and logo; first-view assets
  ≤ 1 MB; every `plays_<season>` `gameId` exists in `games`; the assets'
  default season equals the max `season` with a completed game.
- **Source lines** come from one R list (visual → tables) shipped in
  `teams.json`'s metadata; a test checks that every listed table has a
  dictionary in `inst/dict/` and an anchor on the Data page.
- **Manual mobile check** before merge: Playwright at a 390×844 viewport,
  driving the default path (Teams → Texas → 2026 → a game → scrub → player
  chip → Players → Combine), with screenshots in the PR.

## Build order

1. **Spike + decision record.** Prove OJS + DuckDB-WASM range reads + plotly
   inside the altdoc Quarto site; measure first-view weight and game-open time
   on a phone viewport. Record the architecture (revises decision 0006's
   "OJS later").
2. **Shell.** `explorer.qmd` (`freeze: false`), id-keyed URL-hash state,
   season selector defaulting to the in-progress season, tab bar, lazy tab
   loading, error cards, the margin-equation and "Data:" source-line patterns,
   per-table anchors on `data.qmd`; `teams.json`/`team_season.json` exports +
   contracts.
3. **Teams tab** through the game timeline (`games_*`, `plays_*` exports).
4. **Players tab** (`player_season_*`, `player_outcome` exports).
5. **Combine tab** (shared builder with #64).
6. **Draft & careers tab.** Move the old charts over, drop redshirts, then
   retire `visualizations.qmd`, point the `explore.qmd` tile at the explorer,
   and update NEWS.
7. **Map tab** after #48 publishes.

Each step is its own PR, and `main` stays deployable after each one.
