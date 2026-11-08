# Explorer shell (step 2 of plans/explorer.md) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `vignettes/explorer.qmd`, an OJS page with an id-keyed URL hash,
a season selector defaulting to the in-progress season, lazily loaded tabs,
error cards, the margin-equation and "Data:" source-line patterns, and one
real visual (the selected team's Elo by season), fed by three
contract-checked JSON exports.

**Architecture:** R builds every value. `R/explorer.R` has pure
`build_explorer_*()` functions (tested with testthat on fixtures), a pointblank
`contract_explorer_shell()` wired into `contract_gate`, and one `format = "file"`
target that writes `vignettes/explorer-data/{meta,teams,team_season}.json`
during every `tar_make()`, including the track-mode site build. The page is
plain Quarto OJS with no R chunks. Its hash/state logic lives in small ES
modules under `vignettes/explorer/`, tested with `node --test` and run from
testthat. Decision 0046 has the architecture and budgets.

**Tech Stack:** R (dplyr, jsonlite, pointblank, targets, testthat), Quarto 1.8
OJS (Observable Plot, Inputs), Node ≥ 20 for `node --test`.

**Branch:** `feat/explorer-shell` from `main`. Work in the main checkout: `data/`
is gitignored and Quarto can't render from a hidden worktree path.

---

## Facts the engineer needs

- **Load code** with `pkgload::load_all()`. The repo is never installed
  (decision 0042). Run tests with `Rscript -e 'devtools::test(filter = "explorer")'`.
- **Base pipe `|>`** and `.data$col` in dplyr verbs. Comments explain *why*,
  briefly. Run `air format .` before each commit (the pre-commit hook in
  `.githooks` mirrors CI).
- **`games`** (cleaned target and `data/games.parquet`) has one row per game:
  `id`, `season`, `week`, `seasonType`, `startDate` (ISO string), `completed`,
  `homeId`/`awayId` (CFBD team id, == `teams.team_id`), `homeTeam`/`awayTeam`,
  `homeConference`/`awayConference`, `homeClassification`/`awayClassification`
  (`"fbs"`, `"fcs"`, `"ii"`, `"iii"`, NA), `homePoints`/`awayPoints`,
  `homePregameElo`/`homePostgameElo` (and away). 36,544 completed games;
  6 have NA points.
- **Elo exists only for FBS teams.** FCS sides are almost all NA, and FBS
  2010–2021 is ~90% covered, 2022 on ~100%. FCS team-seasons show W-L with no
  Elo line.
- **`teams`** has `team_id`, `team` (school name), `mascot`, `abbreviation`,
  `classification`, `color`, `alt_color`, `logo_light`, `logo_dark`. All FBS
  (138) and FCS (128) teams have a color and logo. `team_color_values(teams)`
  (`R/viz.R`) is the shared valid-hex filter; `"#6b7280"` is the shared
  fallback grey.
- **`tiers`** (target; `conference_tiers` table) has `season`, `conference`,
  `tier`, `tier_label`, one row per `(season, conference)`.
- **Contracts** follow `contract_team_season()` in `R/contracts.R`: build a
  pointblank agent, `interrogate()`, then `enforce_contract(agent, label,
  stop_on_fail)`. Non-column checks use the row-floor trick
  (`col_vals_equal("ok", TRUE, preconditions = function(x) tibble::tibble(ok = <cond>))`).
  The pipeline records `ok_<x> <- pointblank::all_passed(contract_<x>(..., stop_on_fail = FALSE))`
  and lists it in the `contract_gate` target's `assert_contracts_pass(list(...))`.
- **Dictionaries:** `inst/dict/<table>.yml`, where `dataset:` equals the file name.
  `app_sys("dict")` resolves the directory from the checkout.
- **Site:** `altdoc::render_docs(freeze = TRUE)` copies all of `vignettes/`
  (including `explorer/` and `explorer-data/`) into `_quarto/vignettes/` and
  renders to `docs/`. Runtime-fetched files must be listed under `resources:`.
  Edited pages with R chunks write new `_quarto/_freeze/` entries. Those must
  be committed (the site build reuses them).

## File map

| File | Responsibility |
|---|---|
| `R/explorer.R` (create) | `explorer_default_season()`, `explorer_game_sides()`, `build_explorer_team_season()`, `build_explorer_teams()`, `explorer_sources()`, `build_explorer_meta()`, `explorer_json()`, `explorer_json_gzip_bytes()`, `write_explorer_assets()` |
| `R/contracts.R` (modify, append) | `contract_explorer_shell()` |
| `tests/testthat/test-explorer.R` (create) | R logic + contract tests on fixtures |
| `_targets.R` (modify) | `explorer_*` targets, `ok_explorer`, gate entry, audit rows |
| `vignettes/explorer/state.js` (create) | Hash parse/serialize, season resolution, tab list, defaults |
| `vignettes/explorer/ui.js` (create) | `sourceLine()`, `errorCard()` HTML builders |
| `vignettes/explorer/state.test.mjs`, `ui.test.mjs` (create) | `node --test` unit tests |
| `tests/testthat/test-explorer-js.R` (create) | Runs the node tests from testthat (skips without node or `vignettes/`) |
| `vignettes/explorer/explorer.css` (create) | Tap targets, single column under 600px, tab bar, cards |
| `vignettes/explorer.qmd` (create) | The OJS page |
| `vignettes/data.qmd` (modify) | Per-table anchors `#table-<name>` |
| `.gitignore` | already ignores `vignettes/explorer-data/` |
| `plans/explorer.md` (modify) | Small spec corrections listed in Task 10 |

---

### Task 1: Branch, default season, game sides

**Files:**
- Create: `R/explorer.R`, `tests/testthat/test-explorer.R`

- [ ] **Step 1: Branch**

```bash
git checkout feat/explorer-shell   # already exists; it carries this plan
```

- [ ] **Step 2: Write the failing tests** (`tests/testthat/test-explorer.R`)

```r
# Fixture: two FBS teams (1, 2) and one FCS team (3) across two seasons, plus
# an unplayed game and a D-II game that the export must ignore.
explorer_games_fixture <- function() {
  tibble::tibble(
    id = 1:6,
    season = c(2025L, 2025L, 2025L, 2026L, 2026L, 2026L),
    startDate = c(
      "2025-09-01T19:00:00Z", "2025-09-08T19:00:00Z", "2025-09-15T19:00:00Z",
      "2026-09-05T19:00:00Z", "2026-09-12T19:00:00Z", "2026-09-19T19:00:00Z"
    ),
    completed = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
    homeId = c(1L, 2L, 1L, 2L, 4L, 1L),
    awayId = c(2L, 3L, 3L, 1L, 5L, 2L),
    homeConference = c("SEC", "SEC", "SEC", "SEC", "GLIAC", "SEC"),
    awayConference = c("SEC", "SWAC", "SWAC", "SEC", "GLIAC", "SEC"),
    homeClassification = c("fbs", "fbs", "fbs", "fbs", "ii", "fbs"),
    awayClassification = c("fbs", "fcs", "fcs", "fbs", "ii", "fbs"),
    homePoints = c(30L, 41L, 20L, 17L, 10L, NA),
    awayPoints = c(27L, 3L, 20L, 24L, 7L, NA),
    homePostgameElo = c(1610, 1580, 1600, 1560, NA, NA),
    awayPostgameElo = c(1590, NA, NA, 1640, NA, NA)
  )
}

test_that("explorer_default_season is the latest season with a completed game", {
  g <- explorer_games_fixture()
  expect_equal(explorer_default_season(g), 2026L)
  # Preseason: the new season's only game is unplayed, so it falls back.
  g$completed[g$season == 2026L] <- FALSE
  expect_equal(explorer_default_season(g), 2025L)
  g$completed <- FALSE
  expect_error(explorer_default_season(g), "No completed games")
})

test_that("explorer_game_sides gives one row per team per completed game", {
  sides <- explorer_game_sides(explorer_games_fixture())
  expect_equal(nrow(sides), 2L * 5L)
  expect_setequal(names(sides), c(
    "game_id", "season", "start", "team_id", "conference", "classification",
    "points", "opp_points", "elo_post"
  ))
  g1 <- sides[sides$game_id == 1L, ]
  expect_equal(g1$points[g1$team_id == 2L], 27L)
  expect_equal(g1$opp_points[g1$team_id == 2L], 30L)
})
```

- [ ] **Step 3: Run, expect failure**

Run: `Rscript -e 'devtools::test(filter = "explorer")'`
Expected: FAIL, `could not find function "explorer_default_season"`.

- [ ] **Step 4: Implement** (`R/explorer.R`)

```r
# Explorer assets (plans/explorer.md, decision 0046): slim JSON the OJS page
# fetches at runtime. R computes every derived value; the page only filters
# and draws.

#' Default explorer season
#'
#' The in-progress season: the latest season with a completed game. Before a
#' season's first game this is still the previous season, so the preseason
#' falls back on its own.
#'
#' @param games Cleaned games.
#' @return Integer season.
#' @export
explorer_default_season <- function(games) {
  done <- games$season[games$completed %in% TRUE]
  if (length(done) == 0L) {
    cli::cli_abort("No completed games.")
  }
  as.integer(max(done))
}

#' Team sides of completed games
#'
#' One row per team per completed game (home and away), the base of the
#' team-season export.
#'
#' @param games Cleaned games.
#' @return A tibble: `game_id`, `season`, `start`, `team_id`, `conference`,
#'   `classification`, `points`, `opp_points`, `elo_post`.
#' @export
explorer_game_sides <- function(games) {
  done <- dplyr::filter(games, .data$completed %in% TRUE)
  side <- function(us, them) {
    dplyr::transmute(
      done,
      game_id = .data$id,
      season = .data$season,
      start = .data$startDate,
      team_id = .data[[paste0(us, "Id")]],
      conference = .data[[paste0(us, "Conference")]],
      classification = .data[[paste0(us, "Classification")]],
      points = .data[[paste0(us, "Points")]],
      opp_points = .data[[paste0(them, "Points")]],
      elo_post = .data[[paste0(us, "PostgameElo")]]
    )
  }
  dplyr::bind_rows(side("home", "away"), side("away", "home"))
}
```

- [ ] **Step 5: Run, expect pass**

Run: `Rscript -e 'devtools::test(filter = "explorer")'`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
air format R/explorer.R tests/testthat/test-explorer.R
git add R/explorer.R tests/testthat/test-explorer.R
git commit -m "feat(explorer): default season and team sides of games"
```

### Task 2: Team-season export

**Files:**
- Modify: `R/explorer.R`, `tests/testthat/test-explorer.R`

- [ ] **Step 1: Failing test** (append)

```r
explorer_tiers_fixture <- function() {
  tibble::tibble(
    season = c(2025L, 2025L, 2026L, 2026L),
    conference = c("SEC", "SWAC", "SEC", "SWAC"),
    tier = c(3L, 1L, 3L, 1L),
    tier_label = c("Power", "FCS and below", "Power", "FCS and below")
  )
}

test_that("build_explorer_team_season keeps FBS/FCS sides and counts the record", {
  ts <- build_explorer_team_season(
    explorer_games_fixture(),
    explorer_tiers_fixture()
  )
  # Teams 4 and 5 are D-II; game 6 is unplayed. 2025: teams 1, 2, 3;
  # 2026: teams 1, 2.
  expect_false(any(ts$team_id %in% c(4L, 5L)))
  expect_equal(nrow(ts), 5L)
})

test_that("build_explorer_team_season gets W-L-T, end Elo and tier right", {
  ts <- build_explorer_team_season(
    explorer_games_fixture(),
    explorer_tiers_fixture()
  )
  t1 <- ts[ts$team_id == 1L & ts$season == 2025L, ]
  # Team 1 2025: beat 2 (30-27), tied 3 (20-20).
  expect_equal(c(t1$games, t1$wins, t1$losses, t1$ties), c(2L, 1L, 0L, 1L))
  # End Elo = postgame Elo after the last game with an Elo (game 3).
  expect_equal(t1$elo_end, 1600L)
  expect_equal(t1$tier, 3L)
  expect_equal(t1$classification, "fbs")
  t3 <- ts[ts$team_id == 3L, ]
  expect_true(is.na(t3$elo_end)) # FCS: no Elo
  expect_equal(t3$tier_label, "FCS and below")
  expect_equal(ts$wins + ts$losses + ts$ties, ts$games)
  expect_named(ts, c(
    "team_id", "season", "conference", "classification", "tier",
    "tier_label", "games", "wins", "losses", "ties", "elo_end"
  ))
})
```

- [ ] **Step 2: Run, expect failure**

Run: `Rscript -e 'devtools::test(filter = "explorer")'`
Expected: FAIL, `could not find function "build_explorer_team_season"`.

- [ ] **Step 3: Implement** (append to `R/explorer.R`)

```r
#' Explorer team-season table
#'
#' One row per FBS or FCS team per season with a completed game: record,
#' end-of-season Elo (the postgame Elo after the team's last game that has
#' one; FCS teams have none), and the season-aware conference tier.
#'
#' @param games Cleaned games.
#' @param tiers Conference tiers (`season`, `conference`, `tier`, `tier_label`).
#' @return A tibble keyed by `(team_id, season)`.
#' @export
build_explorer_team_season <- function(games, tiers) {
  explorer_game_sides(games) |>
    dplyr::filter(
      .data$classification %in% c("fbs", "fcs"),
      !is.na(.data$points),
      !is.na(.data$opp_points)
    ) |>
    dplyr::arrange(.data$team_id, .data$season, .data$start) |>
    dplyr::summarise(
      conference = dplyr::last(.data$conference),
      classification = dplyr::last(.data$classification),
      games = dplyr::n(),
      wins = sum(.data$points > .data$opp_points),
      losses = sum(.data$points < .data$opp_points),
      ties = sum(.data$points == .data$opp_points),
      elo_end = as.integer(round(dplyr::last(
        .data$elo_post[!is.na(.data$elo_post)],
        default = NA_real_
      ))),
      .by = c("team_id", "season")
    ) |>
    dplyr::left_join(
      dplyr::select(tiers, "season", "conference", "tier", "tier_label"),
      by = c("season", "conference"),
      relationship = "many-to-one"
    ) |>
    dplyr::select(
      "team_id", "season", "conference", "classification", "tier",
      "tier_label", "games", "wins", "losses", "ties", "elo_end"
    )
}
```

- [ ] **Step 4: Run, expect pass**

Run: `Rscript -e 'devtools::test(filter = "explorer")'`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
air format R/explorer.R tests/testthat/test-explorer.R
git add R/explorer.R tests/testthat/test-explorer.R
git commit -m "feat(explorer): team-season export with record, end Elo, tier"
```

### Task 3: Teams, sources, meta, JSON writer

**Files:**
- Modify: `R/explorer.R`, `tests/testthat/test-explorer.R`

- [ ] **Step 1: Failing tests** (append)

```r
explorer_teams_fixture <- function() {
  tibble::tibble(
    team_id = c(1L, 2L, 3L, 4L, 99L),
    team = c("Texas", "Alabama", "Grambling", "Ferris State", "Unused"),
    mascot = c("Longhorns", "Crimson Tide", "Tigers", "Bulldogs", "X"),
    abbreviation = c("TEX", "ALA", "GRAM", "FSU", "X"),
    classification = c("fbs", "fbs", "fcs", "ii", NA),
    color = c("#bf5700", "#9e1b32", "#null", "#cc0000", "#000000"),
    alt_color = c("#ffffff", "#ffffff", "#000000", "#000000", "#000000"),
    logo_light = c("t.png", "a.png", "g.png", "f.png", NA),
    logo_dark = c("td.png", "ad.png", "gd.png", "fd.png", NA)
  )
}

test_that("build_explorer_teams keeps teams in the export with a valid color", {
  ts <- build_explorer_team_season(
    explorer_games_fixture(),
    explorer_tiers_fixture()
  )
  tm <- build_explorer_teams(explorer_teams_fixture(), ts)
  expect_setequal(tm$team_id, c(1L, 2L, 3L))
  expect_named(tm, c(
    "team_id", "team", "mascot", "abbreviation", "color", "alt_color", "logo"
  ))
  # "#null" is not a color: the shared fallback grey stands in.
  expect_equal(tm$color[tm$team_id == 3L], "#6b7280")
  expect_equal(tm$color[tm$team_id == 1L], "#bf5700")
})

test_that("explorer_sources names only tables that have a dictionary", {
  src <- explorer_sources()
  expect_true(all(c("team_view", "teams_landscape") %in% names(src)))
  dicts <- sub("\\.yml$", "", list.files(app_sys("dict"), "\\.yml$"))
  expect_true(all(unlist(src) %in% dicts))
  expect_true(all(lengths(src) >= 2L)) # keeps them JSON arrays
})

test_that("build_explorer_meta carries the default season and sources", {
  m <- build_explorer_meta(explorer_games_fixture())
  expect_equal(m$default_season, 2026L)
  expect_equal(m$seasons, c(2025L, 2026L))
  expect_equal(m$default_team, 251L)
  expect_equal(m$sources, explorer_sources())
})

test_that("explorer_json writes rows, nulls and scalars the page expects", {
  js <- explorer_json(tibble::tibble(a = c(1L, NA), b = c("x", NA)))
  expect_equal(as.character(js), '[{"a":1,"b":"x"},{"a":null,"b":null}]')
  meta <- explorer_json(list(default_season = 2026L, seasons = c(2025L, 2026L)))
  expect_equal(as.character(meta), '{"default_season":2026,"seasons":[2025,2026]}')
  expect_gt(explorer_json_gzip_bytes(tibble::tibble(a = 1:10)), 0)
})

test_that("write_explorer_assets writes one JSON file per asset and returns paths", {
  dir <- withr::local_tempdir()
  paths <- write_explorer_assets(
    list(meta = list(default_season = 2026L), teams = tibble::tibble(a = 1L)),
    dir
  )
  expect_equal(basename(paths), c("meta.json", "teams.json"))
  expect_true(all(file.exists(paths)))
  expect_equal(
    jsonlite::read_json(file.path(dir, "meta.json"))$default_season,
    2026L
  )
})
```

- [ ] **Step 2: Run, expect failure**

Run: `Rscript -e 'devtools::test(filter = "explorer")'`
Expected: FAIL, `could not find function "build_explorer_teams"`.

- [ ] **Step 3: Implement** (append to `R/explorer.R`)

```r
#' Explorer team dimension
#'
#' Display fields for every team in the team-season export, stored once so
#' `team_season.json` carries ids only (decision 0046). Colors go through the
#' shared valid-hex filter, falling back to the shared grey.
#'
#' @param teams Cleaned teams.
#' @param team_season Output of [build_explorer_team_season()].
#' @return A tibble keyed by `team_id`.
#' @export
build_explorer_teams <- function(teams, team_season) {
  valid <- team_color_values(teams)
  teams |>
    dplyr::filter(.data$team_id %in% team_season$team_id) |>
    dplyr::transmute(
      team_id = .data$team_id,
      team = .data$team,
      mascot = .data$mascot,
      abbreviation = .data$abbreviation,
      color = dplyr::coalesce(unname(valid[.data$team]), "#6b7280"),
      alt_color = .data$alt_color,
      logo = .data$logo_light
    ) |>
    dplyr::arrange(.data$team)
}

#' Source tables behind each explorer visual
#'
#' The page prints these as a "Data:" line linking to each table on the Data
#' page, so readers can look up where a chart comes from.
#'
#' @return A named list: visual key -> character vector of table names.
#' @export
explorer_sources <- function() {
  list(
    teams_landscape = c("games", "teams", "conference_tiers"),
    team_view = c("games", "teams", "conference_tiers"),
    team_season = c("games", "teams"),
    game_timeline = c("plays", "play_types", "games", "play_stats"),
    players = c(
      "player_stats", "roster", "teams", "conference_tiers", "outcomes",
      "picks"
    ),
    combine = c("combine", "outcomes", "picks"),
    careers = c("picks", "nfl_draft_picks", "nfl_rosters", "roster"),
    map = c("teams", "games")
  )
}

#' Explorer page metadata
#'
#' @param games Cleaned games.
#' @return A list: `default_season`, `seasons`, `default_team` (Texas, CFBD
#'   team id 251), `sources`.
#' @export
build_explorer_meta <- function(games) {
  done <- games$season[games$completed %in% TRUE]
  list(
    default_season = explorer_default_season(games),
    seasons = sort(unique(as.integer(done))),
    default_team = 251L,
    sources = explorer_sources()
  )
}

#' Serialize an explorer asset
#'
#' Data frames become arrays of row objects with `null` for NA; length-1
#' vectors become scalars, so `meta.json` reads naturally in JS.
#'
#' @param x A data frame or list.
#' @return A `json` string.
#' @export
explorer_json <- function(x) {
  jsonlite::toJSON(
    x,
    dataframe = "rows",
    na = "null",
    auto_unbox = TRUE,
    digits = NA
  )
}

#' Gzipped size of an explorer asset
#'
#' What GitHub Pages actually transfers; the first-view budget is set in these
#' bytes (decision 0046).
#'
#' @param x A data frame or list.
#' @return Integer bytes.
#' @export
explorer_json_gzip_bytes <- function(x) {
  length(memCompress(charToRaw(explorer_json(x)), "gzip"))
}

#' Write explorer assets
#'
#' @param assets Named list of data frames / lists; names become file names.
#' @param dir Output directory (created if missing).
#' @return The written file paths, for a `format = "file"` target.
#' @export
write_explorer_assets <- function(assets, dir = "vignettes/explorer-data") {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  paths <- file.path(dir, paste0(names(assets), ".json"))
  for (i in seq_along(assets)) {
    writeLines(explorer_json(assets[[i]]), paths[[i]])
  }
  paths
}
```

- [ ] **Step 4: Run, expect pass**

Run: `Rscript -e 'devtools::test(filter = "explorer")'`
Expected: PASS (9 tests). If the `explorer_json` string test fails only on
key order or spacing, print `explorer_json(...)` and check that the JSON is
what the page needs. Change the expectation only if the JSON is right.

- [ ] **Step 5: Commit**

```bash
air format R/explorer.R tests/testthat/test-explorer.R
git add R/explorer.R tests/testthat/test-explorer.R
git commit -m "feat(explorer): team dimension, sources, meta and JSON writer"
```

### Task 4: Shell contract

**Files:**
- Modify: `R/contracts.R` (append), `tests/testthat/test-explorer.R`

- [ ] **Step 1: Failing tests** (append)

```r
explorer_shell_fixture <- function() {
  g <- explorer_games_fixture()
  ts <- build_explorer_team_season(g, explorer_tiers_fixture())
  list(
    games = g,
    team_season = ts,
    teams = build_explorer_teams(explorer_teams_fixture(), ts),
    meta = build_explorer_meta(g)
  )
}

test_that("contract_explorer_shell passes on consistent assets", {
  f <- explorer_shell_fixture()
  agent <- contract_explorer_shell(
    f$teams, f$team_season, f$meta, f$games,
    stop_on_fail = FALSE
  )
  expect_true(pointblank::all_passed(agent))
})

test_that("contract_explorer_shell catches row loss, stale meta and size", {
  f <- explorer_shell_fixture()
  # A dropped team-season breaks the no-silent-loss game count.
  expect_false(pointblank::all_passed(contract_explorer_shell(
    f$teams, f$team_season[-1, ], f$meta, f$games,
    stop_on_fail = FALSE
  )))
  # A team-season with no display row.
  expect_false(pointblank::all_passed(contract_explorer_shell(
    f$teams[f$teams$team_id != 1L, ], f$team_season, f$meta, f$games,
    stop_on_fail = FALSE
  )))
  # Meta that disagrees with the games.
  stale <- f$meta
  stale$default_season <- 2025L
  expect_false(pointblank::all_passed(contract_explorer_shell(
    f$teams, f$team_season, stale, f$games,
    stop_on_fail = FALSE
  )))
  # Over the first-view budget.
  expect_false(pointblank::all_passed(contract_explorer_shell(
    f$teams, f$team_season, f$meta, f$games,
    max_gzip_bytes = 10L,
    stop_on_fail = FALSE
  )))
  expect_error(
    contract_explorer_shell(
      f$teams, f$team_season, stale, f$games,
      stop_on_fail = TRUE
    ),
    "explorer_shell"
  )
})
```

- [ ] **Step 2: Run, expect failure**

Run: `Rscript -e 'devtools::test(filter = "explorer")'`
Expected: FAIL, `could not find function "contract_explorer_shell"`.

- [ ] **Step 3: Implement** (append to `R/contracts.R`)

```r
#' Data contract for the explorer shell assets
#'
#' Guards the first-view assets of the explorer (plans/explorer.md): one row
#' per `(team_id, season)` with a record that adds up; no silent loss (the
#' team-seasons' games equal the FBS/FCS sides of completed, scored games);
#' every team-season has a display row with a color and logo; Elo on every
#' FBS team-season from 2022 on (coverage is ~100% there); `meta` agrees with
#' the games and names only documented tables; and the gzipped first view fits
#' the budget (decision 0046).
#'
#' @param teams Output of [build_explorer_teams()].
#' @param team_season Output of [build_explorer_team_season()].
#' @param meta Output of [build_explorer_meta()].
#' @param games Cleaned games.
#' @param max_gzip_bytes First-view budget in gzipped bytes.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_explorer_shell <- function(
  teams,
  team_season,
  meta,
  games,
  max_gzip_bytes = 250000L,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  expected_games <- explorer_game_sides(games) |>
    dplyr::filter(
      .data$classification %in% c("fbs", "fcs"),
      !is.na(.data$points),
      !is.na(.data$opp_points)
    ) |>
    nrow()
  shown <- dplyr::filter(
    teams,
    !is.na(.data$color),
    !is.na(.data$logo)
  )
  dicts <- sub("\\.yml$", "", list.files(app_sys("dict"), "\\.yml$"))
  gzip_bytes <- sum(vapply(
    list(meta, teams, team_season),
    explorer_json_gzip_bytes,
    integer(1)
  ))
  check <- function(agent, ok) {
    pointblank::col_vals_equal(
      agent,
      "ok",
      TRUE,
      preconditions = function(x) tibble::tibble(ok = ok)
    )
  }
  agent <- pointblank::create_agent(team_season, label = "explorer_shell") |>
    pointblank::col_exists(c(
      "team_id", "season", "conference", "classification", "tier",
      "games", "wins", "losses", "ties", "elo_end"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(team_id, season)) |>
    pointblank::rows_distinct(pointblank::vars(team_id, season)) |>
    pointblank::col_vals_expr(rlang::expr(
      wins + losses + ties == games
    )) |>
    pointblank::col_vals_gt("games", 0L) |>
    pointblank::col_vals_lte("season", meta$default_season) |>
    pointblank::col_vals_not_null(
      pointblank::vars(elo_end),
      preconditions = function(x) {
        dplyr::filter(x, .data$classification == "fbs", .data$season >= 2022L)
      }
    ) |>
    check(nrow(team_season) > 0L) |>
    check(sum(team_season$games) == expected_games) |>
    check(all(team_season$team_id %in% shown$team_id)) |>
    check(identical(meta$default_season, explorer_default_season(games))) |>
    check(all(unlist(meta$sources) %in% dicts)) |>
    check(gzip_bytes <= max_gzip_bytes) |>
    pointblank::interrogate()
  enforce_contract(agent, "explorer_shell", stop_on_fail)
}
```

- [ ] **Step 4: Run, expect pass**

Run: `Rscript -e 'devtools::test(filter = "explorer")'`
Expected: PASS (11 tests).

- [ ] **Step 5: Commit**

```bash
air format R/contracts.R tests/testthat/test-explorer.R
git add R/contracts.R tests/testthat/test-explorer.R
git commit -m "feat(explorer): shell asset contract"
```

### Task 5: Pipeline targets

**Files:**
- Modify: `_targets.R` (three places)

- [ ] **Step 1: Add the explorer targets** right after the
  `tar_target(team_draft, build_team_draft(exits, team_season)),` line (~839):

```r
  # Explorer assets (plans/explorer.md, decision 0046): slim JSON the OJS
  # page fetches at runtime, rebuilt on every tar_make() (including the
  # track-mode site build) so the page follows the weekly refresh.
  tar_target(explorer_team_season, build_explorer_team_season(games, tiers)),
  tar_target(explorer_teams, build_explorer_teams(teams, explorer_team_season)),
  tar_target(explorer_meta, build_explorer_meta(games)),
  tar_target(
    ok_explorer,
    pointblank::all_passed(contract_explorer_shell(
      explorer_teams,
      explorer_team_season,
      explorer_meta,
      games,
      stop_on_fail = FALSE
    ))
  ),
  tar_target(
    explorer_shell_files,
    write_explorer_assets(list(
      meta = explorer_meta,
      teams = explorer_teams,
      team_season = explorer_team_season
    )),
    format = "file"
  ),
```

- [ ] **Step 2: Gate it.** In the `contract_gate` target's list, after
  `team_draft = ok_team_draft`, add a comma and `explorer = ok_explorer`.

- [ ] **Step 3: Audit it.** In `audit_log`'s `dplyr::bind_rows(...)`, after
  the `team_draft` `audit_step(...)` block, add:

```r
      audit_step(
        explorer_team_season,
        "build_explorer_team_season",
        "features",
        games,
        keys = c("team_id", "season"),
        contract_passed = ok_explorer
      ),
```

(Rows drop by design: ~36.5k games collapse to ~4.4k FBS/FCS team-seasons,
like `build_team_season`.)

- [ ] **Step 4: Run the pipeline in track mode**

Run: `Rscript -e 'targets::tar_make()'`
Expected: completes and `contract_gate` passes. Then check:

```bash
ls -la vignettes/explorer-data/
Rscript -e 'm <- jsonlite::read_json("vignettes/explorer-data/meta.json"); str(m[c("default_season","default_team")]); ts <- jsonlite::read_json("vignettes/explorer-data/team_season.json"); cat(length(ts), "team-seasons\n"); for (f in list.files("vignettes/explorer-data", full.names=TRUE)) cat(basename(f), length(memCompress(readBin(f, "raw", file.size(f)), "gzip")), "gz bytes\n")'
```

Expected: `default_season` 2026, `default_team` 251, about 4,400 team-seasons
(FBS + FCS, 2010–2026), and gzipped total ≤ 250 KB. If `ok_explorer` is
FALSE, run `contract_explorer_shell(tar_read(explorer_teams), tar_read(explorer_team_season), tar_read(explorer_meta), tar_read(games))`
interactively to see which step failed, and fix the cause. Don't loosen the
contract.

- [ ] **Step 5: Run the full test suite**

Run: `Rscript -e 'devtools::test()'`
Expected: no failures.

- [ ] **Step 6: Commit**

```bash
air format _targets.R
git add _targets.R
git commit -m "feat(explorer): pipeline targets, gate and audit row for shell assets"
```

### Task 6: Per-table anchors on the Data page

**Files:**
- Modify: `vignettes/data.qmd` (after the `dictionaries` chunk, before
  `### Column-level detail`)

- [ ] **Step 1: Add the anchor list.** Insert:

````markdown
### Tables

Each table below is linked from the explorer's "Data:" lines.

```{r}
#| label: table-anchors
#| results: asis
for (f in dict_files) {
  d <- yaml::read_yaml(f)
  cat(sprintf(
    "- []{#table-%s}**`%s`**: %s\n",
    d$dataset,
    d$dataset,
    d$grain
  ))
}
```
````

- [ ] **Step 2: Render the page alone to check the anchors**

Run: `CFB2NFL_ROOT=$PWD quarto render vignettes/data.qmd --to html --output-dir /tmp/data-check`
Expected: renders. `grep -c 'id="table-' /tmp/data-check/data.html` prints
the number of dictionaries (26 today), and `grep -o 'id="table-games"' /tmp/data-check/data.html`
matches. If a stand-alone render isn't possible outside the site project,
skip this step: Task 9 checks the anchors in the full render.

- [ ] **Step 3: Commit**

```bash
git add vignettes/data.qmd
git commit -m "feat(site): per-table anchors on the Data page for explorer source links"
```

### Task 7: Hash/state and UI helper modules (node-tested)

**Files:**
- Create: `vignettes/explorer/state.js`, `vignettes/explorer/ui.js`,
  `vignettes/explorer/state.test.mjs`, `vignettes/explorer/ui.test.mjs`,
  `tests/testthat/test-explorer-js.R`

- [ ] **Step 1: Write the node tests** (`vignettes/explorer/state.test.mjs`)

```js
import {test} from "node:test";
import assert from "node:assert/strict";
import {TABS, parseHash, toHash, resolveSeason, resolveTeam} from "./state.js";

const meta = {default_season: 2026, seasons: [2024, 2025, 2026], default_team: 251};

test("empty hash gives the defaults", () => {
  assert.deepEqual(parseHash("", meta), {
    tab: "teams", season: 2026, team: 251, game: null, pos: "QB", player: null
  });
});

test("ids parse as integers, player stays a string", () => {
  const s = parseHash("#tab=players&season=2025&team=333&game=401752677&pos=WR&player=4870906", meta);
  assert.equal(s.tab, "players");
  assert.equal(s.season, 2025);
  assert.equal(s.team, 333);
  assert.equal(s.game, 401752677);
  assert.equal(s.pos, "WR");
  assert.equal(s.player, "4870906");
});

test("bad values fall back to defaults", () => {
  const s = parseHash("#tab=nope&season=1999&team=abc&game=1.5", meta);
  assert.equal(s.tab, "teams");
  assert.equal(s.season, 2026);
  assert.equal(s.team, 251);
  assert.equal(s.game, null);
});

test("toHash writes every non-null key in a fixed order", () => {
  const s = {tab: "teams", season: 2026, team: 251, game: null, pos: "QB", player: null};
  assert.equal(toHash(s), "#tab=teams&season=2026&team=251&pos=QB");
  assert.deepEqual(parseHash(toHash({...s, game: 7}), meta), {...s, game: 7});
});

test("resolveSeason and resolveTeam", () => {
  assert.equal(resolveSeason(2025, meta), 2025);
  assert.equal(resolveSeason(2010, meta), 2026);
  const teams = [{team_id: 251}, {team_id: 333}];
  assert.equal(resolveTeam(333, teams, meta), 333);
  assert.equal(resolveTeam(9, teams, meta), 251);
});

test("tabs are the shell's four, Teams first", () => {
  assert.deepEqual(TABS.map(t => t.key), ["teams", "players", "combine", "careers"]);
});
```

`vignettes/explorer/ui.test.mjs`:

```js
import {test} from "node:test";
import assert from "node:assert/strict";
import {sourceLine, errorCard, escapeHtml} from "./ui.js";

test("sourceLine links each table to its Data page anchor", () => {
  assert.equal(
    sourceLine(["games", "teams"]),
    '<p class="explorer-source">Data: <a href="data.html#table-games"><code>games</code></a>, ' +
      '<a href="data.html#table-teams"><code>teams</code></a></p>'
  );
});

test("errorCard names what failed and offers a retry button", () => {
  const html = errorCard("team seasons");
  assert.match(html, /role="alert"/);
  assert.match(html, /Couldn't load team seasons\./);
  assert.match(html, /<button type="button" class="explorer-retry">Retry<\/button>/);
});

test("escapeHtml escapes markup", () => {
  assert.equal(escapeHtml(`<a "b">&`), "&lt;a &quot;b&quot;&gt;&amp;");
});
```

- [ ] **Step 2: Run, expect failure**

Run: `node --test vignettes/explorer/`
Expected: FAIL, cannot find module `./state.js`.

- [ ] **Step 3: Implement** `vignettes/explorer/state.js`

```js
// Explorer URL-hash state (plans/explorer.md, decision 0046). Pure functions,
// unit-tested with node --test; the page wires them to the DOM. Every key is
// written to the hash so a shared link pins the season instead of following
// the in-progress one.

export const TABS = [
  {key: "teams", label: "Teams"},
  {key: "players", label: "Players"},
  {key: "combine", label: "Combine"},
  {key: "careers", label: "Draft & careers"}
];

const KEYS = ["tab", "season", "team", "game", "pos", "player"];
const INTEGER_KEYS = new Set(["season", "team", "game"]);

export function resolveSeason(season, meta) {
  return meta.seasons.includes(season) ? season : meta.default_season;
}

export function resolveTeam(team, teams, meta) {
  return teams.some(t => t.team_id === team) ? team : meta.default_team;
}

export function parseHash(hash, meta) {
  const state = {
    tab: "teams", season: meta.default_season, team: meta.default_team,
    game: null, pos: "QB", player: null
  };
  const params = new URLSearchParams(String(hash ?? "").replace(/^#/, ""));
  for (const key of KEYS) {
    const raw = params.get(key);
    if (raw === null || raw === "") continue;
    if (!INTEGER_KEYS.has(key)) {
      state[key] = raw;
      continue;
    }
    const n = Number(raw);
    if (Number.isInteger(n)) state[key] = n;
  }
  if (!TABS.some(t => t.key === state.tab)) state.tab = "teams";
  state.season = resolveSeason(state.season, meta);
  return state;
}

export function toHash(state) {
  const params = new URLSearchParams();
  for (const key of KEYS) {
    if (state[key] !== null && state[key] !== undefined) params.set(key, String(state[key]));
  }
  return "#" + params.toString();
}
```

`vignettes/explorer/ui.js`:

```js
// Small HTML builders shared by every explorer tab (plans/explorer.md).

export function escapeHtml(s) {
  return String(s).replace(/[&<>"]/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"})[c]);
}

// The "Data:" line under each visual: one link per source table to its
// anchor on the Data page.
export function sourceLine(tables, href = "data.html") {
  const links = tables
    .map(t => `<a href="${href}#table-${escapeHtml(t)}"><code>${escapeHtml(t)}</code></a>`)
    .join(", ");
  return `<p class="explorer-source">Data: ${links}</p>`;
}

export function errorCard(what) {
  return `<div class="explorer-card explorer-error" role="alert"><p>Couldn't load ${escapeHtml(what)}.</p>` +
    `<button type="button" class="explorer-retry">Retry</button></div>`;
}
```

- [ ] **Step 4: Run, expect pass**

Run: `node --test vignettes/explorer/`
Expected: all tests pass (9).

- [ ] **Step 5: Run them from testthat** (`tests/testthat/test-explorer-js.R`)

```r
test_that("explorer JS modules pass their node tests", {
  node <- Sys.which("node")
  skip_if(!nzchar(node), "node is not installed")
  # vignettes/ is .Rbuildignored, so R CMD check skips; devtools::test() runs.
  dir <- testthat::test_path("..", "..", "vignettes", "explorer")
  skip_if_not(dir.exists(dir), "vignettes/explorer not present")
  files <- list.files(dir, "\\.test\\.mjs$", full.names = TRUE)
  expect_gt(length(files), 0L)
  out <- suppressWarnings(system2(node, c("--test", files), stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  if (is.null(status)) status <- 0L
  expect_equal(status, 0L, info = paste(out, collapse = "\n"))
})
```

Run: `Rscript -e 'devtools::test(filter = "explorer-js")'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
air format tests/testthat/test-explorer-js.R
git add vignettes/explorer/ tests/testthat/test-explorer-js.R
git commit -m "feat(explorer): hash state and UI helper modules with node tests"
```

### Task 8: The page

**Files:**
- Modify: `vignettes/explorer/ui.js`, `vignettes/explorer/ui.test.mjs` (add `loadOnce`)
- Create: `vignettes/explorer/explorer.css`, `vignettes/explorer.qmd`

- [ ] **Step 1: Failing test for `loadOnce`** (append to `ui.test.mjs`, and add
  `loadOnce` to its import line)

```js
test("loadOnce loads a tab's data once and retries after a failure", async () => {
  const cache = new Map();
  let calls = 0;
  const load = async () => { calls += 1; return calls; };
  assert.equal(await loadOnce(cache, "players", load), 1);
  assert.equal(await loadOnce(cache, "players", load), 1);
  assert.equal(calls, 1);
  let fail = true;
  const flaky = async () => { if (fail) throw new Error("offline"); return "ok"; };
  await assert.rejects(loadOnce(cache, "combine", flaky), /offline/);
  fail = false;
  assert.equal(await loadOnce(cache, "combine", flaky), "ok");
});
```

Run: `node --test vignettes/explorer/` and expect a FAIL (`loadOnce` is not
exported).

- [ ] **Step 2: Implement** (append to `ui.js`)

```js
// Lazy tab data: the first open starts the load, later opens reuse it, and a
// failed load is forgotten so Retry can try again.
export function loadOnce(cache, key, load) {
  if (!cache.has(key)) {
    cache.set(key, Promise.resolve().then(load).catch(error => {
      cache.delete(key);
      throw error;
    }));
  }
  return cache.get(key);
}
```

Run: `node --test vignettes/explorer/`. Expected: 10 pass.

- [ ] **Step 3: Write `vignettes/explorer/explorer.css`**

```css
/* Explorer (plans/explorer.md): touch-first sizing and a sticky header. */
.explorer-header {
  position: sticky;
  top: 0;
  z-index: 10;
  background: var(--bs-body-bg, #fff);
  padding: 0.5rem 0;
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  align-items: center;
  border-bottom: 1px solid #e5e7eb;
}
.explorer-header select { min-height: 44px; font-size: 1rem; }
/* Inputs.radio as a tab bar: hide the dots, make each label a 44px pill. */
.explorer-tabs form > div { display: flex; flex-wrap: wrap; gap: 0.4rem; }
.explorer-tabs input[type="radio"] { position: absolute; opacity: 0; }
.explorer-tabs form > div > label {
  min-height: 44px;
  display: inline-flex;
  align-items: center;
  padding: 0.5rem 1rem;
  border: 1px solid #d1d5db;
  border-radius: 999px;
  font-size: 1rem;
  cursor: pointer;
}
.explorer-tabs form > div > label:has(input:checked) {
  background: #111827;
  color: #fff;
  border-color: #111827;
}
.explorer-tabs input[type="radio"]:focus-visible + * { outline: 2px solid #2563eb; }
.explorer-card { border: 1px solid #e5e7eb; border-radius: 0.5rem; padding: 1rem; margin: 1rem 0; font-size: 1.05rem; }
.explorer-error { border-color: #b91c1c; }
.explorer-retry { min-height: 44px; min-width: 44px; padding: 0.5rem 1rem; font-size: 1rem; }
.explorer-source { font-size: 0.95rem; color: #4b5563; }
.explorer-tab svg { max-width: 100%; height: auto; }
@media (max-width: 600px) {
  .explorer-header { flex-direction: column; align-items: stretch; }
}
```

- [ ] **Step 4: Write `vignettes/explorer.qmd`**

The page has no R chunks, so it does nothing at knit time and its frozen
render stays correct (decision 0046). Every number comes from the JSON at
runtime. The cells are `echo: false` because this is an app page; the source
stays a click away through the site's code tools.

````markdown
---
title: "Explorer"
description: "Drill from conferences to teams, games and players, season by season."
vignette: >
  %\VignetteIndexEntry{Explorer}
  %\VignetteEngine{quarto::html}
  %\VignetteEncoding{UTF-8}
resources:
  - explorer-data/**
css: explorer/explorer.css
toc: false
---

```{ojs}
//| echo: false
import {TABS, parseHash, toHash, resolveTeam} from "./explorer/state.js"
import {sourceLine, errorCard, loadOnce} from "./explorer/ui.js"
```

```{ojs}
//| echo: false
//| output: false
mutable retry = 0
tabCache = new Map()
function asNode(markup) {
  const el = document.createElement("div");
  el.innerHTML = markup;
  return el.firstElementChild;
}
```

```{ojs}
//| echo: false
//| output: false
// The first view: meta, teams and team seasons (~60 KB gzipped).
shell = {
  retry;
  try {
    const [meta, teams, teamSeason] = await Promise.all([
      FileAttachment("explorer-data/meta.json").json(),
      FileAttachment("explorer-data/teams.json").json(),
      FileAttachment("explorer-data/team_season.json").json()
    ]);
    return {meta, teams, teamSeason, teamById: new Map(teams.map(t => [t.team_id, t]))};
  } catch (error) {
    return {error};
  }
}
// Cells below read `ready`, which never resolves after a failed load, so
// they wait quietly behind the error card instead of throwing.
ready = shell.error ? new Promise(() => {}) : shell
```

```{ojs}
//| echo: false
shellStatus = {
  if (!shell.error) return document.createComment("loaded");
  const card = asNode(errorCard("the explorer data"));
  card.querySelector("button").onclick = () => { mutable retry = retry + 1; };
  return card;
}
```

```{ojs}
//| echo: false
//| output: false
// Hash state, re-read when the reader edits the hash or presses back.
hashState = Generators.observe(notify => {
  const read = () => {
    const s = parseHash(location.hash, ready.meta);
    s.team = resolveTeam(s.team, ready.teams, ready.meta);
    notify(s);
  };
  read();
  addEventListener("hashchange", read);
  addEventListener("popstate", read);
  return () => {
    removeEventListener("hashchange", read);
    removeEventListener("popstate", read);
  };
})
```

::: {.explorer-header}
::: {.explorer-tabs}
```{ojs}
//| echo: false
viewof tab = Inputs.radio(new Map(TABS.map(t => [t.label, t.key])), {value: hashState.tab})
```
:::

```{ojs}
//| echo: false
viewof season = Inputs.select(ready.meta.seasons.slice().reverse(), {
  label: "Season",
  value: hashState.season,
  format: String
})
```
:::

```{ojs}
//| echo: false
//| output: false
// Write every key back; the first write replaces the bare URL instead of
// adding a history entry.
{
  const next = toHash({...hashState, tab, season, team});
  if (next === location.hash) return;
  if (location.hash) history.pushState(null, "", next);
  else history.replaceState(null, "", next);
}
```

```{ojs}
//| echo: false
//| output: false
// Show one tab's section at a time.
{
  for (const t of TABS) {
    const el = document.getElementById(`tab-${t.key}`);
    if (el) el.hidden = t.key !== tab;
  }
}
```

::: {#tab-teams .explorer-tab}
## Teams

```{ojs}
//| echo: false
// Every FBS/FCS team, independent of the season: an input that depended on
// `season` would be rebuilt (and reset to the hash's team) on each change.
viewof team = Inputs.select(
  new Map(ready.teams.map(t => [t.team, t.team_id])),
  {label: "Team", value: hashState.team}
)
```

```{ojs}
//| echo: false
eloChart = {
  const info = ready.teamById.get(team);
  const rows = ready.teamSeason.filter(d => d.team_id === team && d.elo_end !== null);
  if (rows.length === 0) {
    return asNode(`<div class="explorer-card">${info.team} has no Elo rating: CFBD rates FBS teams only.</div>`);
  }
  const record = d => `${d.wins}-${d.losses}${d.ties ? "-" + d.ties : ""}`;
  return Plot.plot({
    height: 340,
    marginLeft: 56,
    style: {fontSize: "16px"},
    x: {label: "Season", tickFormat: String},
    y: {label: "End-of-season Elo", grid: true},
    marks: [
      Plot.ruleX([season], {stroke: "#9ca3af", strokeDasharray: "4,4"}),
      Plot.line(rows, {x: "season", y: "elo_end", stroke: info.color, strokeWidth: 3}),
      Plot.dot(rows, {
        x: "season", y: "elo_end", fill: info.color, r: 6,
        title: d => `${d.season}: Elo ${d.elo_end}, record ${record(d)}`,
        tip: true
      })
    ]
  });
}
```

::: {.column-margin}
**End-of-season Elo** is the team's CFBD Elo rating after its last rated game
of the season. A rating gap of $D$ points gives the higher-rated team an
expected win probability of

$$E = \frac{1}{1 + 10^{-D/400}}$$

so a 100-point edge is about a 64% favorite.
:::

```{ojs}
//| echo: false
asNode(sourceLine(ready.meta.sources.team_view))
```
:::

::: {#tab-players .explorer-tab}
## Players

::: {.explorer-card}
The players landscape (every player at a position, season by season) is the
next piece of the explorer.
:::
:::

::: {#tab-combine .explorer-tab}
## Combine

::: {.explorer-card}
The combine view (height, weight and 40 in 3D, by draft outcome) is coming.
:::
:::

::: {#tab-careers .explorer-tab}
## Draft & careers

::: {.explorer-card}
Draft classes, NFL careers and transfers move here from the Visualizations
page.
:::
:::
````

`loadOnce` and `tabCache` aren't used by the shell's placeholder tabs. Steps
3–5 call `loadOnce(tabCache, "<tab>", () => ...)` inside each tab. They're
defined here so the pattern ships with the shell.

- [ ] **Step 5: Commit**

```bash
git add vignettes/explorer.qmd vignettes/explorer/
git commit -m "feat(explorer): page shell with hash state, tabs, Elo view, margin and source patterns"
```

### Task 9: Render, serve, verify on a phone viewport

**Files:** none new in the repo. `_quarto/_freeze/vignettes/data/` changes are
committed.

- [ ] **Step 1: Render the site**

Run: `CFB2NFL_ROOT=$PWD Rscript -e 'altdoc::render_docs(freeze = TRUE)'`
(≈5 min; long timeout).
Expected: completes. `ls docs/vignettes/explorer.html docs/vignettes/explorer-data/ docs/vignettes/explorer/`
lists the page, the three JSON files, and `state.js`/`ui.js`/`explorer.css`.
`grep -c 'id="table-' docs/vignettes/data.html` equals the number of
`inst/dict/*.yml` files.

- [ ] **Step 2: Serve with a static server** (save as `/tmp/explorer-serve.mjs`;
the npm registry is unreachable through the local proxy, so no `npx`)

```js
import {createServer} from "node:http";
import {createReadStream, statSync} from "node:fs";
import {extname, join, normalize} from "node:path";
const root = process.argv[2], port = Number(process.argv[3] ?? 8080);
const types = {".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript",
  ".css": "text/css", ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png",
  ".parquet": "application/octet-stream", ".woff2": "font/woff2"};
createServer((req, res) => {
  let path = join(root, normalize(decodeURIComponent(new URL(req.url, "http://x").pathname)));
  try { if (statSync(path).isDirectory()) path = join(path, "index.html"); } catch {}
  let size;
  try { size = statSync(path).size; } catch { res.writeHead(404).end(); return; }
  const type = types[extname(path)] ?? "application/octet-stream";
  const m = /bytes=(\d*)-(\d*)/.exec(req.headers.range ?? "");
  if (m) {
    const start = m[1] ? Number(m[1]) : size - Number(m[2]);
    const end = m[1] && m[2] ? Number(m[2]) : size - 1;
    res.writeHead(206, {"Content-Type": type, "Accept-Ranges": "bytes",
      "Content-Range": `bytes ${start}-${end}/${size}`, "Content-Length": end - start + 1});
    createReadStream(path, {start, end}).pipe(res);
  } else {
    res.writeHead(200, {"Content-Type": type, "Accept-Ranges": "bytes", "Content-Length": size});
    createReadStream(path).pipe(res);
  }
}).listen(port);
```

Run (background): `node /tmp/explorer-serve.mjs docs 8080`

- [ ] **Step 3: Verify with Playwright MCP** at `browser_resize` 390×844. Load
  the tools via ToolSearch. Check each item and record pass/fail with
  evidence (snapshot text, `location.hash`, console):

  1. `http://localhost:8080/vignettes/explorer.html` (no hash): no console
     errors apart from a favicon 404. The Teams tab is selected, Season shows
     `2026` (not `2,026`), Team shows Texas, the Elo chart renders, and
     `location.hash` is `#tab=teams&season=2026&team=251&pos=QB`.
     `history.length` did not grow from the first write.
  2. Change Season to 2024. The hash shows `season=2024`, and the dashed
     rule moves to 2024.
  3. Pick Alabama, then change Season. Team stays Alabama.
  4. Tap the Players tab. Only the Players section is visible, the hash
     shows `tab=players`, and `browser_navigate_back` returns to Teams.
  5. Navigate to `#tab=teams&season=2025&team=333`. Season 2025 and
     Alabama (`team_id` 333) are selected. Navigate to `#team=999999`.
     Team falls back to Texas.
  6. Pick an FCS team (e.g. Montana). The card says it has no Elo rating.
  7. The margin note with the formula is visible. At 390px wide it renders
     inline below the chart, and KaTeX renders it, not raw `$$`.
  8. The "Data:" line links to `data.html#table-games` etc., and following
     one lands on the anchor.
  9. Tap targets: `browser_evaluate` checks that every tab label and select is
     ≥ 44px tall
     (`[...document.querySelectorAll('.explorer-tabs label, .explorer-header select')].map(e => e.getBoundingClientRect().height)`).
  10. Error card: rename `docs/vignettes/explorer-data/teams.json` to
      `teams.json.bak` and reload. An alert card with Retry appears and no
      OJS error boxes do. Rename it back, tap Retry, and the page loads.
  11. `performance.getEntriesByType("resource")`: the three JSON files are
      the only data requests, and their gzipped total (`gzip -c f | wc -c`
      summed) is ≤ 250 KB.

Fix anything that fails in the files from Tasks 7–8 (re-render to check),
committing each fix as `fix(explorer): <what>`. Kill the server when done.

- [ ] **Step 4: Commit the Data page's freeze update and restore anything else**

```bash
git status --short
git add _quarto/_freeze/vignettes/data/
git commit -m "chore(site): refresh Data page freeze for table anchors"
```

Any other tracked file the render changed (except `_quarto/_freeze/vignettes/data/`
and new `_quarto/_freeze/vignettes/explorer/` entries, if Quarto made some) goes
back with `git checkout -- <path>`. If an `explorer` freeze directory was
created, commit it too. Freeze files must be tracked or the site build loses
the page's render (issue #69).

### Task 10: Spec touch-ups, NEWS, PR

**Files:**
- Modify: `plans/explorer.md`, `NEWS.md`

- [ ] **Step 1: Spec corrections** in `plans/explorer.md`:
  - **Data assets table:** add a `meta.json` row (grain: page metadata, with
    `default_season`, `seasons`, `default_team` and `sources`; ~2 KB; first
    view). Change the `teams.json` grain to "team (name, mascot,
    abbreviation, color, alt color, logo)", since conference-by-season lives in
    `team_season.json`.
  - **Testing and contracts:** replace "Source lines come from one R list
    (visual → tables) shipped in `teams.json`'s metadata" with "shipped in
    `meta.json` (`explorer_sources()`)".
  - **Build order:** tick step 2 (`[x]`).
- [ ] **Step 2: NEWS.** Under the top (development) heading of `NEWS.md`, add:

```markdown
- New **Explorer** page (preview, not yet in the navigation): pick a season
  and a team to see its end-of-season Elo across every season since 2010. The
  link keeps your place, so it can be shared. It is the shell for the
  team, game, player and combine views coming next
  ([decision 0046](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0046-ojs-explorer.md), #70).
```

- [ ] **Step 3: Final checks**

Run: `air format . && Rscript -e 'devtools::test()' && node --test vignettes/explorer/`
Expected: no failures.

- [ ] **Step 4: Commit, push, open the PR** (using the `gh` R package, not the CLI)

```bash
git add plans/explorer.md NEWS.md
git commit -m "docs(explorer): spec touch-ups and NEWS for the shell"
git push -u origin feat/explorer-shell
```

```r
gh::gh("POST /repos/{owner}/{repo}/pulls", owner = "ngiangre", repo = "cfb2nfl",
  head = "feat/explorer-shell", base = "main",
  title = "feat(explorer): page shell, hash state, first exports (#70 step 2)",
  body = paste(readLines("/tmp/explorer-shell-pr.md"), collapse = "\n"))
```

`/tmp/explorer-shell-pr.md` holds the PR description: what Tasks 1–9 built, the
Task 9 checklist results (pass/fail per item), `Refs #70`, and the closing
line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. The
controller writes it from the task reports.

The site build runs `tar_make()` in track mode, which now writes the explorer
assets before rendering. CI must be green before merging.
