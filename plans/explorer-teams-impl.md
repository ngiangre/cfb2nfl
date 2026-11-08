# Explorer Teams tab (step 3 of plans/explorer.md) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Teams tab end to end: a conference landscape, the team
view, the team-season strip of games, and the game timeline (score margin and
cumulative PPA over the game clock, with a scrub crosshair and play card).
The drill runs conference → team → season → game → play.

**Architecture:** As in step 2, R builds every value.
- New `R/explorer_games.R` builds two assets:
  - `team_games_<season>.json`: one row per FBS/FCS team per completed game,
    from that team's side.
  - `plays_<season>.parquet`: one row per play, with elapsed seconds, home
    score/margin, home cumulative PPA, scoring/turnover flags and players.
    Sorted by game with small row groups.
- Two contracts guard them, and the gate includes them.
- The page stacks the levels vertically, the mobile-first drill:
  1. Landscape
  2. Team
  3. Season
  4. Game

  Picking at one level updates the levels below.
- JS keeps two node-tested modules:
  - `teams.js`: filtering and timeline flips.
  - `plays.js`: row-group pruning and a reader that takes the hyparquet module
    as a parameter, so tests never touch the network.

**Tech Stack:** R (dplyr, arrow, jsonlite, pointblank, targets, testthat),
Quarto OJS (Observable Plot, Inputs), hyparquet 1.x (jsDelivr ESM), Node ≥ 20.

**Branch:** `feat/explorer-teams` (exists; carries this plan). Work in the
main checkout.

---

## Facts the engineer needs

- **Read step 2's code first:** `R/explorer.R`, `contract_explorer_shell()`
  at the end of `R/contracts.R`, the `explorer_*` targets in `_targets.R`
  (search "Explorer assets"), `vignettes/explorer.qmd`, and
  `vignettes/explorer/{state,ui}.js`. Conventions there apply: base pipe,
  `.data$`, `relationship =` on every join, roxygen with `@export`, and
  `devtools::document()` after roxygen edits, committing `NAMESPACE`/`man/`.
  pointblank column names used in `vars()` go into `R/globals.R`.
- **`games` columns** (cleaned target): `id`, `season`, `week`, `seasonType`,
  `startDate` (ISO string, same format everywhere, so string sort is chronological),
  `completed`, `neutralSite`, `homeId`/`awayId`, `homeTeam`/`awayTeam`,
  `homePoints`/`awayPoints`, `homePregameElo`/`awayPregameElo`,
  `homePostgameElo`/`awayPostgameElo`,
  `homePostgameWinProbability`/`awayPostgameWinProbability`.
- **`plays` columns** (cleaned target, 3.1M rows, 2010–2026, `format =
  "parquet"`): `id` (string, unique), `gameId` (int), `season`, `driveNumber`,
  `playNumber`, `period` (1–4, OT 5–9), `clock_minutes`, `clock_seconds` (43
  NA rows in total; OT plays have a dummy clock), `offense`, `defense` (school
  names; they match `teams.team` exactly), `offenseScore`, `defenseScore`,
  `down`, `distance`, `yardsToGoal`, `playType`, `playText`, `ppa` (NA on
  ~24% of plays), `scoring` (logical).
- **`play_stats`** (cleaned target): `playId` (== `plays.id`), `athleteId`
  (string), `athleteName`, `statType`. It has rows for 2026 only today.
- **Turnover play types:** `Fumble Recovery (Opponent)`, `Fumble Return
  Touchdown`, `Interception`, `Interception Return Touchdown`, `Pass
  Interception`, `Pass Interception Return`.
- **Many completed games have no plays** (2,172 in 2025, mostly D-II/D-III).
  The game view shows a "no play-by-play" card for those.
- **Elo is FBS-only.** FCS lines in the landscape use win share instead (new
  `win_pct` column, Task 1).
- **hyparquet API** (verified in the spike): `asyncBufferFromUrl({url})`,
  `parquetMetadataAsync(file)`, `parquetReadObjects({file, metadata, rowStart,
  rowEnd})`. Row-group statistics are at
  `metadata.row_groups[i].columns[j].meta_data.statistics.{min_value,max_value}`
  and the column name at `meta_data.path_in_schema`. `num_rows` may be a
  BigInt.
- **Setting an OJS input from code:** `view.value = v;
  view.dispatchEvent(new Event("input", {bubbles: true}))`.
- **Plot interactivity:** a mark wrapped in `Plot.pointer()`/`Plot.pointerX()`
  makes the figure's `.value` the pointed datum, and the figure fires `input`
  events. A `click` listener reading `fig.value` turns a tap into a selection.
- **Verification uses the Task 9 server and Playwright procedure** from
  `plans/explorer-shell-impl.md` (Task 9 Step 2 server script; render with
  `CFB2NFL_ROOT=$PWD Rscript -e 'altdoc::render_docs(freeze = TRUE)'`).

## File map

| File | Responsibility |
|---|---|
| `R/explorer.R` (modify) | `win_pct` on team-seasons; new `explorer_sources()` keys stay as they are |
| `R/explorer_games.R` (create) | `explorer_elo_expectation()`, `build_explorer_team_games()`, `explorer_turnover_types()`, `explorer_elapsed()`, `build_explorer_plays()`, `write_explorer_team_games()`, `write_explorer_plays()` |
| `R/contracts.R` (append) | `contract_explorer_team_games()`, `contract_explorer_plays()` |
| `R/globals.R` (modify) | new pointblank column names |
| `tests/testthat/test-explorer-games.R` (create) | fixtures + tests for the above |
| `_targets.R` (modify) | targets, gate entries, audit rows |
| `vignettes/explorer/teams.js` + `teams.test.mjs` (create) | `teamGames`, `effectiveGame`, `landscapePanels`, `timelineFor`, `parsePlayers`, `formatRecord` |
| `vignettes/explorer/plays.js` + `plays.test.mjs` (create) | `pickRowGroups`, `readGamePlays` |
| `vignettes/explorer/explorer.css` (modify) | panel grid, chips, game tiles, play card |
| `vignettes/explorer.qmd` (modify) | Teams tab rewrite + `game`/`player` inputs in the writer |
| `plans/explorer.md`, `NEWS.md` (modify) | tick step 3, NEWS |

---

### Task 1: Shared fixtures and `win_pct`

**Files:**
- Create: `tests/testthat/helper-explorer.R`
- Modify: `tests/testthat/test-explorer.R` (delete the fixture functions moved
  out), `R/explorer.R` (`build_explorer_team_season()`), `R/contracts.R`
  (`contract_explorer_shell()`)

- [ ] **Step 1: Move the fixtures.** Cut `explorer_games_fixture()`,
  `explorer_tiers_fixture()`, `explorer_teams_fixture()` and
  `explorer_shell_fixture()` out of `tests/testthat/test-explorer.R` into a new
  `tests/testthat/helper-explorer.R`, which testthat sources before every test
  file. Then extend `explorer_games_fixture()` with the columns step 3 needs,
  adding these entries to its `tibble::tibble(...)` call (existing columns
  and values unchanged):

```r
    week = c(1L, 2L, 3L, 1L, 2L, 3L),
    seasonType = "regular",
    neutralSite = c(FALSE, FALSE, TRUE, FALSE, FALSE, FALSE),
    homeTeam = c("Texas", "Alabama", "Texas", "Alabama", "Ferris State", "Texas"),
    awayTeam = c("Alabama", "Grambling", "Grambling", "Texas", "Grand Valley State", "Alabama"),
    homePregameElo = c(1600, 1570, 1610, 1570, NA, NA),
    awayPregameElo = c(1600, NA, NA, 1630, NA, NA),
    homePostgameWinProbability = c(0.7, 0.99, 0.5, 0.3, NA, NA),
    awayPostgameWinProbability = c(0.3, 0.01, 0.5, 0.7, NA, NA)
```

(Team ids: 1 Texas, 2 Alabama, 3 Grambling (FCS), 4 Ferris State and 5 Grand
Valley State (D-II).)

Run: `Rscript -e 'devtools::test(filter = "explorer")'`. Expected: still all
pass (only the fixtures moved).

- [ ] **Step 2: Failing test** (append to `tests/testthat/test-explorer.R`)

```r
test_that("build_explorer_team_season carries win share for the FCS landscape", {
  ts <- build_explorer_team_season(
    explorer_games_fixture(),
    explorer_tiers_fixture()
  )
  t1 <- ts[ts$team_id == 1L & ts$season == 2025L, ]
  # One win and one tie in two games: ties count half.
  expect_equal(t1$win_pct, 0.75)
  expect_true(all(ts$win_pct >= 0 & ts$win_pct <= 1))
  expect_equal(names(ts)[ncol(ts)], "win_pct")
})
```

Run, expect FAIL (`win_pct` missing).

- [ ] **Step 3: Implement.** In `build_explorer_team_season()`, add after the
  tier fill (before the final `dplyr::select`):

```r
    dplyr::mutate(
      win_pct = round((.data$wins + 0.5 * .data$ties) / .data$games, 3)
    ) |>
```

and add `"win_pct"` as the last name in the final `dplyr::select(...)`.
Document it in the roxygen `@return` ("... and `win_pct`, wins plus half of
ties over games"). In `contract_explorer_shell()`, add `"win_pct"` to
`col_exists(...)` and add
`pointblank::col_vals_between("win_pct", 0, 1) |>` after the
`col_vals_gt("games", 0L)` step. Update the `expect_named(...)` in the
existing "W-L-T, end Elo and tier" test to end with `"win_pct"`.

- [ ] **Step 4: Run, expect pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "explorer")'`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
air format R/ tests/
git add tests/testthat/helper-explorer.R tests/testthat/test-explorer.R R/explorer.R R/contracts.R man/
git commit -m "feat(explorer): win share on team-seasons; shared explorer fixtures"
```

### Task 2: Team-games export

**Files:**
- Create: `R/explorer_games.R`, `tests/testthat/test-explorer-games.R`

- [ ] **Step 1: Failing tests** (`tests/testthat/test-explorer-games.R`)

```r
test_that("explorer_elo_expectation is the Elo win probability", {
  expect_equal(explorer_elo_expectation(1600, 1600), 0.5)
  expect_equal(round(explorer_elo_expectation(1700, 1600), 3), 0.64)
  expect_true(is.na(explorer_elo_expectation(1600, NA)))
})

test_that("build_explorer_team_games gives each FBS/FCS team's side of each game", {
  g <- explorer_games_fixture()
  ts <- build_explorer_team_season(g, explorer_tiers_fixture())
  tg <- build_explorer_team_games(g, ts, play_game_ids = c(1L, 4L))
  # No row loss against the team-season records.
  expect_equal(nrow(tg), sum(ts$games))
  expect_false(any(tg$team_id %in% c(4L, 5L)))
  expect_named(tg, c(
    "season", "week", "season_type", "start", "game_id", "team_id",
    "opp_id", "opp_name", "site", "home", "points", "opp_points", "result",
    "elo_pre", "elo_post", "elo_delta", "wp_pre", "wp_post", "has_plays"
  ))
  g1 <- tg[tg$game_id == 1L & tg$team_id == 1L, ]
  expect_equal(g1$site, "home")
  expect_equal(g1$result, "W")
  expect_equal(c(g1$elo_pre, g1$elo_post, g1$elo_delta), c(1600L, 1610L, 10L))
  expect_equal(g1$wp_pre, 0.5)
  expect_equal(g1$wp_post, 0.7)
  expect_true(g1$has_plays)
  a1 <- tg[tg$game_id == 1L & tg$team_id == 2L, ]
  expect_equal(c(a1$site, a1$result, a1$opp_name), c("away", "L", "Texas"))
  g3 <- tg[tg$game_id == 3L & tg$team_id == 1L, ]
  expect_equal(c(g3$site, g3$result), c("neutral", "T"))
  # Neutral sites keep the listed home side, which the play timeline needs.
  expect_true(g3$home)
  expect_false(a1$home)
  expect_true(is.na(g3$wp_pre)) # FCS opponent has no Elo
  expect_false(g3$has_plays)
})
```

Run: `Rscript -e 'devtools::test(filter = "explorer-games")'`. Expected: FAIL
(`could not find function "explorer_elo_expectation"`).

- [ ] **Step 2: Implement** (`R/explorer_games.R`)

```r
# Explorer game-level assets (plans/explorer.md step 3, decision 0046): each
# team's side of each game, and slim per-season play files for the game
# timeline.

#' Elo expected win probability
#'
#' @param elo,opp_elo Ratings of the team and its opponent.
#' @return The team's expected win probability, `1 / (1 + 10^(-(elo - opp_elo) / 400))`.
#' @export
explorer_elo_expectation <- function(elo, opp_elo) {
  1 / (1 + 10^(-(elo - opp_elo) / 400))
}

#' Explorer team-games table
#'
#' One row per FBS/FCS team per completed, scored game, from that team's side:
#' site (and whether the team is the listed home side, kept at neutral sites), score, result, Elo before and after, the Elo expected win
#' probability before kickoff, CFBD's postgame win probability, and whether
#' the game has play-by-play. Rows match the team-season records exactly.
#'
#' @param games Cleaned games.
#' @param team_season Output of [build_explorer_team_season()].
#' @param play_game_ids Game ids that have rows in `plays`.
#' @return A tibble keyed by `(team_id, game_id)`.
#' @export
build_explorer_team_games <- function(games, team_season, play_game_ids) {
  done <- dplyr::filter(
    games,
    .data$completed %in% TRUE,
    !is.na(.data$homePoints),
    !is.na(.data$awayPoints)
  )
  side <- function(us, them) {
    dplyr::transmute(
      done,
      season = .data$season,
      week = .data$week,
      season_type = .data$seasonType,
      start = .data$startDate,
      game_id = .data$id,
      team_id = .data[[paste0(us, "Id")]],
      opp_id = .data[[paste0(them, "Id")]],
      opp_name = .data[[paste0(them, "Team")]],
      site = dplyr::if_else(.data$neutralSite %in% TRUE, "neutral", us),
      home = us == "home",
      points = .data[[paste0(us, "Points")]],
      opp_points = .data[[paste0(them, "Points")]],
      elo_pre_raw = .data[[paste0(us, "PregameElo")]],
      opp_elo_pre = .data[[paste0(them, "PregameElo")]],
      elo_post_raw = .data[[paste0(us, "PostgameElo")]],
      wp_post = round(.data[[paste0(us, "PostgameWinProbability")]], 3)
    )
  }
  dplyr::bind_rows(side("home", "away"), side("away", "home")) |>
    dplyr::semi_join(team_season, by = c("team_id", "season")) |>
    dplyr::mutate(
      result = dplyr::case_when(
        .data$points > .data$opp_points ~ "W",
        .data$points < .data$opp_points ~ "L",
        .default = "T"
      ),
      elo_pre = as.integer(round(.data$elo_pre_raw)),
      elo_post = as.integer(round(.data$elo_post_raw)),
      elo_delta = as.integer(round(.data$elo_post_raw - .data$elo_pre_raw)),
      wp_pre = round(explorer_elo_expectation(.data$elo_pre_raw, .data$opp_elo_pre), 3),
      has_plays = .data$game_id %in% play_game_ids
    ) |>
    dplyr::arrange(.data$team_id, .data$season, .data$start) |>
    dplyr::select(
      "season", "week", "season_type", "start", "game_id", "team_id",
      "opp_id", "opp_name", "site", "home", "points", "opp_points", "result",
      "elo_pre", "elo_post", "elo_delta", "wp_pre", "wp_post", "has_plays"
    )
}
```

- [ ] **Step 3: Run, expect pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "explorer-games")'`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
air format R/explorer_games.R tests/testthat/test-explorer-games.R
git add R/explorer_games.R tests/testthat/test-explorer-games.R NAMESPACE man/
git commit -m "feat(explorer): team-games export from each team's side"
```

### Task 3: Plays export

**Files:**
- Modify: `R/explorer_games.R`, `tests/testthat/helper-explorer.R`,
  `tests/testthat/test-explorer-games.R`

- [ ] **Step 1: Fixtures** (append to `helper-explorer.R`)

```r
# Game 1: Texas (home, id 1) vs Alabama (id 2), with an OT play; game 4:
# Alabama home. Scores are each play's offense/defense score.
explorer_plays_fixture <- function() {
  tibble::tibble(
    id = c("11", "12", "13", "14", "15", "41"),
    gameId = c(1L, 1L, 1L, 1L, 1L, 4L),
    season = c(2025L, 2025L, 2025L, 2025L, 2025L, 2026L),
    driveNumber = c(1L, 1L, 2L, 3L, 4L, 1L),
    playNumber = c(1L, 2L, 1L, 1L, 1L, 1L),
    period = c(1L, 1L, 2L, 4L, 5L, 1L),
    clock_minutes = c(15L, 10L, 7L, 0L, 15L, 14L),
    clock_seconds = c(0L, 30L, 30L, 5L, 0L, 0L),
    offense = c("Texas", "Texas", "Alabama", "Texas", "Alabama", "Alabama"),
    defense = c("Alabama", "Alabama", "Texas", "Alabama", "Texas", "Texas"),
    offenseScore = c(0L, 7L, 0L, 27L, 24L, 0L),
    defenseScore = c(0L, 0L, 7L, 24L, 27L, 0L),
    down = c(1L, 2L, 1L, 3L, 1L, 1L),
    distance = c(10L, 5L, 10L, 2L, 10L, 10L),
    yardsToGoal = c(75L, 40L, 80L, 30L, 25L, 75L),
    playType = c(
      "Rush", "Passing Touchdown", "Pass Interception Return",
      "Field Goal Good", "Rush", "Rush"
    ),
    playText = c("a", "b", "c", "d", "e", "f"),
    ppa = c(0.5, 2.0, -1.5, NA, 0.25, 0.1),
    scoring = c(FALSE, TRUE, FALSE, TRUE, FALSE, FALSE)
  )
}

explorer_play_stats_fixture <- function() {
  tibble::tibble(
    playId = c("12", "12"),
    athleteId = c("p1", "p2"),
    athleteName = c("Passer One", "Receiver Two"),
    statType = c("Completion", "Reception")
  )
}
```

- [ ] **Step 2: Failing tests** (append to `test-explorer-games.R`)

```r
test_that("explorer_elapsed runs 0-3600 in regulation and gives OT 300 s slots", {
  expect_equal(explorer_elapsed(1L, 15L, 0L, 0), 0L)
  expect_equal(explorer_elapsed(2L, 7L, 30L, 0), 1350L)
  expect_equal(explorer_elapsed(4L, 0L, 0L, 0), 3600L)
  expect_equal(explorer_elapsed(5L, 15L, 0L, 0), 3600L)
  expect_equal(explorer_elapsed(5L, 15L, 0L, 0.5), 3750L)
  expect_equal(explorer_elapsed(6L, 15L, 0L, 0), 3900L)
  expect_true(is.na(explorer_elapsed(3L, NA, 0L, 0)))
  # A bad clock is clamped into its quarter.
  expect_equal(explorer_elapsed(1L, 20L, 0L, 0), 0L)
})

test_that("build_explorer_plays puts every play on the home team's scale", {
  p <- build_explorer_plays(
    explorer_plays_fixture(),
    explorer_games_fixture(),
    explorer_teams_fixture(),
    explorer_play_stats_fixture()
  )
  expect_equal(nrow(p), nrow(explorer_plays_fixture()))
  expect_named(p, c(
    "season", "game_id", "play_id", "period", "clock", "elapsed",
    "offense_id", "home_score", "away_score", "home_margin", "home_cum_ppa",
    "down", "distance", "yards_to_goal", "play_type", "play_text",
    "scoring", "turnover", "players"
  ))
  g1 <- p[p$game_id == 1L, ]
  expect_equal(g1$play_id, c("11", "12", "13", "14", "15"))
  expect_equal(g1$elapsed, c(0L, 270L, 1350L, 3595L, 3600L))
  expect_equal(g1$clock, c("15:00", "10:30", "7:30", "0:05", "OT1"))
  expect_equal(g1$offense_id, c(1L, 1L, 2L, 1L, 2L))
  expect_equal(g1$home_score, c(0L, 7L, 7L, 27L, 27L))
  expect_equal(g1$away_score, c(0L, 0L, 0L, 24L, 24L))
  expect_equal(g1$home_margin, c(0L, 7L, 7L, 3L, 3L))
  # Texas's PPA counts up, Alabama's counts down; NA counts as 0.
  expect_equal(g1$home_cum_ppa, c(0.5, 2.5, 4.0, 4.0, 3.75))
  expect_equal(g1$turnover, c(FALSE, FALSE, TRUE, FALSE, FALSE))
  expect_equal(g1$scoring, c(FALSE, TRUE, FALSE, TRUE, FALSE))
  expect_equal(
    jsonlite::fromJSON(g1$players[2])$name,
    c("Passer One", "Receiver Two")
  )
  expect_true(is.na(g1$players[1]))
  g4 <- p[p$game_id == 4L, ]
  expect_equal(g4$home_cum_ppa, 0.1) # Alabama is home in game 4
})
```

Run: `Rscript -e 'devtools::test(filter = "explorer-games")'`. Expected: FAIL
(`could not find function "explorer_elapsed"`).

- [ ] **Step 3: Implement** (append to `R/explorer_games.R`)

```r
#' Play types that change possession by turnover
#'
#' @return Character vector of CFBD `playType` values.
#' @export
explorer_turnover_types <- function() {
  c(
    "Fumble Recovery (Opponent)",
    "Fumble Return Touchdown",
    "Interception",
    "Interception Return Touchdown",
    "Pass Interception",
    "Pass Interception Return"
  )
}

#' Elapsed game time in seconds
#'
#' Regulation runs 0 to 3600 seconds (four 900-second quarters, the clock
#' clamped into its quarter). Overtime has no clock, so each overtime period
#' gets a 300-second slot and its plays are spread evenly by order.
#'
#' @param period Period (1-4 regulation, 5+ overtime).
#' @param clock_minutes,clock_seconds Clock remaining in the period.
#' @param overtime_position Play's position within its period, in `[0, 1)`.
#' @return Integer seconds since kickoff (`NA` for a missing regulation clock).
#' @export
explorer_elapsed <- function(
  period,
  clock_minutes,
  clock_seconds,
  overtime_position
) {
  remaining <- pmin(pmax(clock_minutes * 60 + clock_seconds, 0), 900)
  regulation <- (period - 1) * 900 + (900 - remaining)
  overtime <- 3600 + (period - 5 + overtime_position) * 300
  as.integer(round(ifelse(period <= 4, regulation, overtime)))
}

#' Explorer plays table
#'
#' One row per play, in game order, with everything the game timeline draws
#' already computed: elapsed seconds, the score and margin from the home
#' team's side, cumulative PPA from the home side (the home offense's PPA
#' minus the away offense's, NA counted as 0), scoring and turnover flags, and
#' the players credited on the play as a JSON array (`NA` when none). The page
#' flips signs for the away team.
#'
#' @param plays Cleaned plays.
#' @param games Cleaned games.
#' @param teams Cleaned teams.
#' @param play_stats Cleaned play stats.
#' @return A tibble keyed by `play_id`, one row per input play.
#' @export
build_explorer_plays <- function(plays, games, teams, play_stats) {
  homes <- dplyr::select(games, gameId = "id", home_team = "homeTeam")
  offense_ids <- dplyr::select(teams, offense = "team", offense_id = "team_id")
  players <- play_stats |>
    dplyr::summarise(
      players = as.character(jsonlite::toJSON(data.frame(
        id = .data$athleteId,
        name = .data$athleteName,
        stat = .data$statType
      ))),
      .by = "playId"
    )
  plays |>
    dplyr::left_join(homes, by = "gameId", relationship = "many-to-one") |>
    dplyr::left_join(offense_ids, by = "offense", relationship = "many-to-one") |>
    dplyr::left_join(
      players,
      by = c("id" = "playId"),
      relationship = "one-to-one"
    ) |>
    dplyr::arrange(.data$gameId, .data$driveNumber, .data$playNumber) |>
    dplyr::mutate(
      overtime_position = (dplyr::row_number() - 1) / dplyr::n(),
      .by = c("gameId", "period")
    ) |>
    dplyr::mutate(
      home_offense = dplyr::coalesce(.data$offense == .data$home_team, FALSE),
      home_score = dplyr::if_else(
        .data$home_offense,
        .data$offenseScore,
        .data$defenseScore
      ),
      away_score = dplyr::if_else(
        .data$home_offense,
        .data$defenseScore,
        .data$offenseScore
      ),
      home_cum_ppa = round(
        cumsum(
          dplyr::if_else(.data$home_offense, 1, -1) *
            dplyr::coalesce(.data$ppa, 0)
        ),
        2
      ),
      .by = "gameId"
    ) |>
    dplyr::transmute(
      season = .data$season,
      game_id = .data$gameId,
      play_id = .data$id,
      period = .data$period,
      clock = dplyr::case_when(
        .data$period > 4L ~ paste0("OT", .data$period - 4L),
        is.na(.data$clock_minutes) | is.na(.data$clock_seconds) ~ NA_character_,
        .default = sprintf("%d:%02d", .data$clock_minutes, .data$clock_seconds)
      ),
      elapsed = explorer_elapsed(
        .data$period,
        .data$clock_minutes,
        .data$clock_seconds,
        .data$overtime_position
      ),
      offense_id = .data$offense_id,
      home_score = .data$home_score,
      away_score = .data$away_score,
      home_margin = .data$home_score - .data$away_score,
      home_cum_ppa = .data$home_cum_ppa,
      down = .data$down,
      distance = .data$distance,
      yards_to_goal = .data$yardsToGoal,
      play_type = .data$playType,
      play_text = .data$playText,
      scoring = .data$scoring %in% TRUE,
      turnover = .data$playType %in% explorer_turnover_types(),
      players = .data$players
    )
}
```

(`coalesce(..., FALSE)` keeps `home_offense` from being `NA` when a game is
missing from `games`. The plays contract catches that case.)

- [ ] **Step 4: Run, expect pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "explorer-games")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
air format R/explorer_games.R tests/testthat/
git add R/explorer_games.R tests/testthat/ NAMESPACE man/
git commit -m "feat(explorer): plays export with elapsed time, home margin and cumulative PPA"
```

### Task 4: Per-season writers

**Files:**
- Modify: `R/explorer_games.R`, `tests/testthat/test-explorer-games.R`

- [ ] **Step 1: Failing tests** (append)

```r
test_that("write_explorer_team_games writes one JSON file per season", {
  dir <- withr::local_tempdir()
  g <- explorer_games_fixture()
  ts <- build_explorer_team_season(g, explorer_tiers_fixture())
  tg <- build_explorer_team_games(g, ts, play_game_ids = 1L)
  paths <- write_explorer_team_games(tg, dir)
  expect_equal(basename(paths), c("team_games_2025.json", "team_games_2026.json"))
  back <- jsonlite::read_json(paths[[1]], simplifyVector = TRUE)
  expect_equal(nrow(back), sum(tg$season == 2025L))
})

test_that("write_explorer_plays writes season parquet in game order with small row groups", {
  dir <- withr::local_tempdir()
  p <- build_explorer_plays(
    explorer_plays_fixture(),
    explorer_games_fixture(),
    explorer_teams_fixture(),
    explorer_play_stats_fixture()
  )
  paths <- write_explorer_plays(p, dir, chunk_size = 2L)
  expect_equal(basename(paths), c("plays_2025.parquet", "plays_2026.parquet"))
  back <- arrow::read_parquet(paths[[1]])
  expect_equal(back$play_id, c("11", "12", "13", "14", "15"))
  expect_false("season" %in% names(back))
  reader <- arrow::ParquetFileReader$create(paths[[1]])
  expect_equal(reader$num_row_groups, 3L) # 5 rows in chunks of 2
})
```

Run, expect FAIL.

- [ ] **Step 2: Implement** (append to `R/explorer_games.R`)

```r
#' Write the per-season team-games JSON files
#'
#' @param team_games Output of [build_explorer_team_games()].
#' @param dir Output directory.
#' @return The written paths, `team_games_<season>.json`.
#' @export
write_explorer_team_games <- function(
  team_games,
  dir = "vignettes/explorer-data"
) {
  by_season <- split(team_games, team_games$season)
  names(by_season) <- paste0("team_games_", names(by_season))
  write_explorer_assets(by_season, dir)
}

#' Write the per-season plays parquet files
#'
#' Rows stay in game order and row groups stay small, so each group's
#' `game_id` min/max statistics let the page fetch one game with a couple of
#' range requests (decision 0046).
#'
#' @param explorer_plays Output of [build_explorer_plays()].
#' @param dir Output directory.
#' @param chunk_size Rows per row group.
#' @return The written paths, `plays_<season>.parquet`.
#' @export
write_explorer_plays <- function(
  explorer_plays,
  dir = "vignettes/explorer-data",
  chunk_size = 5000L
) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  seasons <- sort(unique(explorer_plays$season))
  paths <- file.path(dir, sprintf("plays_%d.parquet", seasons))
  for (i in seq_along(seasons)) {
    explorer_plays |>
      dplyr::filter(.data$season == seasons[[i]]) |>
      dplyr::select(-"season") |>
      arrow::write_parquet(paths[[i]], chunk_size = chunk_size)
  }
  paths
}
```

- [ ] **Step 3: Run, expect pass**, then commit:

```bash
Rscript -e 'devtools::document(); devtools::test(filter = "explorer-games")'
air format R/explorer_games.R tests/testthat/test-explorer-games.R
git add R/explorer_games.R tests/testthat/test-explorer-games.R NAMESPACE man/
git commit -m "feat(explorer): per-season team-games JSON and plays parquet writers"
```

### Task 5: Contracts

**Files:**
- Modify: `R/contracts.R` (append), `R/globals.R`,
  `tests/testthat/test-explorer-games.R`

- [ ] **Step 1: Failing tests** (append)

```r
explorer_games_assets_fixture <- function() {
  g <- explorer_games_fixture()
  ts <- build_explorer_team_season(g, explorer_tiers_fixture())
  plays <- explorer_plays_fixture()
  list(
    games = g,
    team_season = ts,
    team_games = build_explorer_team_games(g, ts, unique(plays$gameId)),
    plays = plays,
    explorer_plays = build_explorer_plays(
      plays, g, explorer_teams_fixture(), explorer_play_stats_fixture()
    )
  )
}

test_that("contract_explorer_team_games passes, and catches loss and bad results", {
  f <- explorer_games_assets_fixture()
  ok <- function(tg) {
    pointblank::all_passed(contract_explorer_team_games(
      tg, f$team_season, stop_on_fail = FALSE
    ))
  }
  expect_true(ok(f$team_games))
  expect_false(ok(f$team_games[-1, ]))
  bad <- f$team_games
  bad$result[1] <- "L"
  expect_false(ok(bad))
  bad <- f$team_games
  bad$wp_pre[1] <- 1.5
  expect_false(ok(bad))
  expect_error(
    contract_explorer_team_games(f$team_games[-1, ], f$team_season),
    "explorer_team_games"
  )
})

test_that("contract_explorer_plays passes, and catches loss and orphans", {
  f <- explorer_games_assets_fixture()
  ok <- function(p, games = f$games) {
    pointblank::all_passed(contract_explorer_plays(
      p, f$plays, games, stop_on_fail = FALSE
    ))
  }
  expect_true(ok(f$explorer_plays))
  expect_false(ok(f$explorer_plays[-1, ]))
  expect_false(ok(f$explorer_plays, games = f$games[f$games$id != 4L, ]))
  bad <- f$explorer_plays
  bad$home_margin[2] <- 99L
  expect_false(ok(bad))
})
```

Run, expect FAIL.

- [ ] **Step 2: Implement** (append to `R/contracts.R`)

```r
#' Data contract for the explorer team-games table
#'
#' Guards [build_explorer_team_games()]: one row per `(team_id, game_id)`; no
#' loss against the team-season records; a result that matches the score;
#' win probabilities in 0 to 1; and an Elo change that equals post minus pre.
#'
#' @param team_games Output of [build_explorer_team_games()].
#' @param team_season Output of [build_explorer_team_season()].
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_explorer_team_games <- function(
  team_games,
  team_season,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  check <- function(agent, ok) {
    pointblank::col_vals_equal(
      agent,
      "ok",
      TRUE,
      preconditions = function(x) tibble::tibble(ok = ok)
    )
  }
  agent <- pointblank::create_agent(team_games, label = "explorer_team_games") |>
    pointblank::col_vals_not_null(pointblank::vars(team_id, game_id, season, result)) |>
    pointblank::rows_distinct(pointblank::vars(team_id, game_id)) |>
    pointblank::col_vals_in_set("result", c("W", "L", "T")) |>
    pointblank::col_vals_expr(rlang::expr(
      (result == "W") == (points > opp_points) &
        (result == "L") == (points < opp_points)
    )) |>
    pointblank::col_vals_between("wp_pre", 0, 1, na_pass = TRUE) |>
    pointblank::col_vals_between("wp_post", 0, 1, na_pass = TRUE) |>
    pointblank::col_vals_expr(
      rlang::expr(abs(elo_delta - (elo_post - elo_pre)) <= 1L),
      preconditions = function(x) {
        dplyr::filter(x, !is.na(.data$elo_pre), !is.na(.data$elo_post))
      }
    ) |>
    check(nrow(team_games) > 0L) |>
    check(nrow(team_games) == sum(team_season$games)) |>
    pointblank::interrogate()
  enforce_contract(agent, "explorer_team_games", stop_on_fail)
}

#' Data contract for the explorer plays table
#'
#' Guards [build_explorer_plays()]: one row per input play (no loss); every
#' play's game is in `games`; the margin equals the home score minus the away
#' score; cumulative PPA is never missing; and at least 99.9% of plays have an
#' elapsed time (the rest have a missing clock).
#'
#' @param explorer_plays Output of [build_explorer_plays()].
#' @param plays Cleaned plays.
#' @param games Cleaned games.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_explorer_plays <- function(
  explorer_plays,
  plays,
  games,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  check <- function(agent, ok) {
    pointblank::col_vals_equal(
      agent,
      "ok",
      TRUE,
      preconditions = function(x) tibble::tibble(ok = ok)
    )
  }
  agent <- pointblank::create_agent(explorer_plays, label = "explorer_plays") |>
    pointblank::col_vals_not_null(pointblank::vars(game_id, play_id, period, home_cum_ppa)) |>
    pointblank::rows_distinct(pointblank::vars(play_id)) |>
    pointblank::col_vals_expr(rlang::expr(home_margin == home_score - away_score)) |>
    pointblank::col_vals_gte("elapsed", 0L, na_pass = TRUE) |>
    check(nrow(explorer_plays) == nrow(plays)) |>
    check(all(explorer_plays$game_id %in% games$id)) |>
    check(mean(!is.na(explorer_plays$elapsed)) >= 0.999) |>
    pointblank::interrogate()
  enforce_contract(agent, "explorer_plays", stop_on_fail)
}
```

- [ ] **Step 3: Globals.** Add every bare column name used above in
  `vars()`/`expr()` that `R/globals.R` doesn't already list: `game_id`,
  `result`, `points`, `opp_points`, `elo_delta`, `elo_post`, `elo_pre`,
  `play_id`, `period`, `home_cum_ppa`, `home_margin`, `home_score`,
  `away_score`, `season` (check each against the file first).

- [ ] **Step 4: Run, expect pass**, then commit:

```bash
Rscript -e 'devtools::document(); devtools::test(filter = "explorer")'
air format R/ tests/
git add R/contracts.R R/globals.R tests/testthat/test-explorer-games.R NAMESPACE man/
git commit -m "feat(explorer): team-games and plays contracts"
```

### Task 6: Pipeline targets

**Files:**
- Modify: `_targets.R`

- [ ] **Step 1: Targets.** Right after the `explorer_shell_files` target, add:

```r
  # Teams tab (plans/explorer.md step 3): each team's side of each game, and
  # the plays the game timeline draws. explorer_plays is ~3M rows, so it is
  # stored as parquet rather than rds.
  tar_target(
    explorer_team_games,
    build_explorer_team_games(
      games,
      explorer_team_season,
      unique(plays$gameId)
    )
  ),
  tar_target(
    explorer_plays,
    build_explorer_plays(plays, games, teams, play_stats),
    format = "parquet"
  ),
  tar_target(
    ok_explorer_team_games,
    pointblank::all_passed(contract_explorer_team_games(
      explorer_team_games,
      explorer_team_season,
      stop_on_fail = FALSE
    ))
  ),
  tar_target(
    ok_explorer_plays,
    pointblank::all_passed(contract_explorer_plays(
      explorer_plays,
      plays,
      games,
      stop_on_fail = FALSE
    ))
  ),
  tar_target(
    explorer_game_files,
    c(
      write_explorer_team_games(explorer_team_games),
      write_explorer_plays(explorer_plays)
    ),
    format = "file"
  ),
```

- [ ] **Step 2: Gate.** In `contract_gate`'s list, after `explorer = ok_explorer`, add
  `explorer_team_games = ok_explorer_team_games` and
  `explorer_plays = ok_explorer_plays`.

- [ ] **Step 3: Audit rows.** After the `build_explorer_team_season` audit row,
  add:

```r
      audit_step(
        explorer_team_games,
        "build_explorer_team_games",
        "features",
        games,
        keys = c("team_id", "game_id"),
        contract_passed = ok_explorer_team_games
      ),
      audit_step(
        explorer_plays,
        "build_explorer_plays",
        "features",
        plays,
        keys = "play_id",
        contract_passed = ok_explorer_plays
      ),
```

- [ ] **Step 4: Run in track mode and measure**

Run: `Rscript -e 'targets::tar_make()'` (long timeout). Expected: the gate
passes. Then:

```bash
ls -la vignettes/explorer-data/ | head -50
Rscript -e 'f <- list.files("vignettes/explorer-data", "^team_games_.*json$", full.names = TRUE); cat("team_games files:", length(f), " max gz KB:", round(max(sapply(f, function(x) length(memCompress(readBin(x, "raw", file.size(x)), "gzip")))) / 1024), "\n"); p <- list.files("vignettes/explorer-data", "^plays_.*parquet$", full.names = TRUE); cat("plays files:", length(p), " total MB:", round(sum(file.size(p)) / 1e6, 1), " largest MB:", round(max(file.size(p)) / 1e6, 1), "\n"); r <- arrow::ParquetFileReader$create(p[length(p)]); cat("row groups in", basename(p[length(p)]), ":", r$num_row_groups, "\n")'
```

Expected: 17 `team_games_*.json` (each ≤ ~80 KB gz), 17 `plays_*.parquet`
(each < 100 MB; the GitHub Pages per-file limit), and dozens of row groups per
plays file. Record the numbers for the PR.

- [ ] **Step 5: Full tests, commit**

```bash
Rscript -e 'devtools::test()'
air format _targets.R
git add _targets.R
git commit -m "feat(explorer): pipeline targets, gate and audit rows for team games and plays"
```

### Task 7: JS modules for the Teams tab

**Files:**
- Create: `vignettes/explorer/teams.js`, `vignettes/explorer/teams.test.mjs`,
  `vignettes/explorer/plays.js`, `vignettes/explorer/plays.test.mjs`

- [ ] **Step 1: Failing tests** (`teams.test.mjs`)

```js
import {test} from "node:test";
import assert from "node:assert/strict";
import {formatRecord, teamGames, effectiveGame, landscapePanels, timelineFor, parsePlayers} from "./teams.js";

const games = [
  {game_id: 2, team_id: 251, start: "2025-09-08T00:00:00.000Z", has_plays: true},
  {game_id: 1, team_id: 251, start: "2025-09-01T00:00:00.000Z", has_plays: true},
  {game_id: 3, team_id: 251, start: "2025-09-15T00:00:00.000Z", has_plays: false},
  {game_id: 9, team_id: 333, start: "2025-09-01T00:00:00.000Z", has_plays: true}
];

test("formatRecord shows ties only when there are some", () => {
  assert.equal(formatRecord({wins: 9, losses: 3, ties: 0}), "9-3");
  assert.equal(formatRecord({wins: 5, losses: 5, ties: 1}), "5-5-1");
});

test("teamGames keeps one team's games in kickoff order", () => {
  assert.deepEqual(teamGames(games, 251).map(g => g.game_id), [1, 2, 3]);
});

test("effectiveGame keeps a valid pick, else the latest game with plays", () => {
  const tg = teamGames(games, 251);
  assert.equal(effectiveGame(1, tg), 1);
  assert.equal(effectiveGame(999, tg), 2);
  assert.equal(effectiveGame(null, [{game_id: 5, has_plays: false}]), 5);
  assert.equal(effectiveGame(null, []), null);
});

test("landscapePanels groups by the season's conference, Power first", () => {
  const ts = [
    {team_id: 1, season: 2025, conference: "SEC", classification: "fbs", tier: 3, elo_end: 1700, win_pct: 0.8},
    {team_id: 1, season: 2024, conference: "Big 12", classification: "fbs", tier: 3, elo_end: 1650, win_pct: 0.7},
    {team_id: 2, season: 2025, conference: "Sun Belt", classification: "fbs", tier: 2, elo_end: 1500, win_pct: 0.5},
    {team_id: 3, season: 2025, conference: "SWAC", classification: "fcs", tier: 1, elo_end: null, win_pct: 0.6}
  ];
  const fbs = landscapePanels(ts, 2025, "fbs");
  assert.deepEqual(fbs.map(p => p.conference), ["SEC", "Sun Belt"]);
  assert.equal(fbs[0].metric, "elo_end");
  // Team 1's 2024 Big 12 season stays on its SEC line.
  assert.deepEqual(fbs[0].rows.map(d => d.season).sort(), [2024, 2025]);
  const fcs = landscapePanels(ts, 2025, "fcs");
  assert.equal(fcs[0].metric, "win_pct");
  assert.deepEqual(fcs[0].teamIds, [3]);
});

test("timelineFor flips margin and PPA for the away team and drops untimed plays", () => {
  const plays = [
    {elapsed: 0, home_margin: 0, home_cum_ppa: 0.5, home_score: 0, away_score: 0},
    {elapsed: null, home_margin: 7, home_cum_ppa: 1, home_score: 7, away_score: 0},
    {elapsed: 600, home_margin: 7, home_cum_ppa: 2.5, home_score: 7, away_score: 0}
  ];
  const home = timelineFor(plays, true);
  assert.deepEqual(home.map(d => d.margin), [0, 7]);
  assert.deepEqual(home.map(d => d.team_score), [0, 7]);
  const away = timelineFor(plays, false);
  assert.deepEqual(away.map(d => d.margin), [0, -7]);
  assert.deepEqual(away.map(d => d.cum_ppa), [-0.5, -2.5]);
  assert.deepEqual(away.map(d => d.opp_score), [0, 7]);
});

test("parsePlayers reads the JSON array and tolerates nothing", () => {
  assert.deepEqual(parsePlayers('[{"id":"p1","name":"A","stat":"Rush"}]'), [{id: "p1", name: "A", stat: "Rush"}]);
  assert.deepEqual(parsePlayers(null), []);
  assert.deepEqual(parsePlayers("not json"), []);
});
```

`plays.test.mjs`:

```js
import {test} from "node:test";
import assert from "node:assert/strict";
import {pickRowGroups, readGamePlays} from "./plays.js";

const stats = (lo, hi) => ({meta_data: {path_in_schema: ["game_id"], statistics: {min_value: lo, max_value: hi}}});
const metadata = {
  row_groups: [
    {num_rows: 3n, columns: [stats(1, 2)]},
    {num_rows: 2n, columns: [stats(2, 4)]},
    {num_rows: 4n, columns: [stats(5, 9)]}
  ]
};

test("pickRowGroups returns the row ranges whose game_id span covers the game", () => {
  assert.deepEqual(pickRowGroups(metadata, 2), [{rowStart: 0, rowEnd: 3}, {rowStart: 3, rowEnd: 5}]);
  assert.deepEqual(pickRowGroups(metadata, 7), [{rowStart: 5, rowEnd: 9}]);
  assert.deepEqual(pickRowGroups(metadata, 99), []);
});

test("pickRowGroups reads every group when statistics are missing", () => {
  const bare = {row_groups: [{num_rows: 2, columns: [{meta_data: {path_in_schema: ["game_id"]}}]}]};
  assert.deepEqual(pickRowGroups(bare, 1), [{rowStart: 0, rowEnd: 2}]);
});

test("readGamePlays reads only the picked groups, filters to the game, caches metadata", async () => {
  const rows = [
    {game_id: 1}, {game_id: 2}, {game_id: 2},
    {game_id: 2}, {game_id: 4},
    {game_id: 5}, {game_id: 6}, {game_id: 7}, {game_id: 9}
  ];
  let metaCalls = 0;
  const reads = [];
  const hp = {
    asyncBufferFromUrl: async ({url}) => ({url}),
    parquetMetadataAsync: async () => { metaCalls += 1; return metadata; },
    parquetReadObjects: async ({rowStart, rowEnd}) => { reads.push([rowStart, rowEnd]); return rows.slice(rowStart, rowEnd); }
  };
  const cache = new Map();
  const got = await readGamePlays(hp, "plays_2025.parquet", 2, cache);
  assert.equal(got.length, 3);
  assert.deepEqual(reads, [[0, 3], [3, 5]]);
  await readGamePlays(hp, "plays_2025.parquet", 7, cache);
  assert.equal(metaCalls, 1);
});
```

Run: `node --test vignettes/explorer/teams.test.mjs vignettes/explorer/plays.test.mjs`.
Expected: FAIL (modules missing).

(`deepEqual` treats `-0` and `0` as different, so `timelineFor` adds `+ 0` to
return `0`, not `-0`, for a level score.)

- [ ] **Step 2: Implement** `vignettes/explorer/teams.js`

```js
// Teams-tab helpers (plans/explorer.md step 3). R computes every value; these
// only filter, order and flip signs, and are unit-tested with node --test.

export function formatRecord(d) {
  return `${d.wins}-${d.losses}${d.ties ? "-" + d.ties : ""}`;
}

// One team's games in a season, in kickoff order (ISO strings sort by time).
export function teamGames(rows, teamId) {
  return rows.filter(d => d.team_id === teamId).sort((a, b) => a.start.localeCompare(b.start));
}

// The game to show: the reader's pick if it belongs to this team-season, else
// the latest game with play-by-play, else the latest game.
export function effectiveGame(gameId, games) {
  if (games.some(g => g.game_id === gameId)) return gameId;
  const withPlays = games.filter(g => g.has_plays);
  const pick = (withPlays.length ? withPlays : games).at(-1);
  return pick ? pick.game_id : null;
}

// Conference panels for a season: membership as of that season, each panel
// carrying its teams' whole history so their lines span every season. FBS
// panels plot end-of-season Elo; FCS has no Elo, so its panels plot win share.
export function landscapePanels(teamSeason, season, classification) {
  const metric = classification === "fbs" ? "elo_end" : "win_pct";
  const panels = new Map();
  for (const d of teamSeason) {
    if (d.season !== season || d.classification !== classification) continue;
    const conference = d.conference ?? "Independent";
    if (!panels.has(conference)) panels.set(conference, {conference, tier: d.tier ?? 0, teams: new Set()});
    panels.get(conference).teams.add(d.team_id);
  }
  return [...panels.values()]
    .map(p => ({
      conference: p.conference,
      tier: p.tier,
      metric,
      teamIds: [...p.teams],
      rows: teamSeason.filter(d => p.teams.has(d.team_id) && d[metric] !== null)
    }))
    .sort((a, b) => b.tier - a.tier || a.conference.localeCompare(b.conference));
}

// One game's plays from the selected team's side: margin and cumulative PPA
// flip sign for the away team. Plays without an elapsed time are dropped.
export function timelineFor(plays, isHome) {
  const sign = isHome ? 1 : -1;
  return plays
    .filter(p => p.elapsed !== null && p.elapsed !== undefined)
    .map(p => ({
      ...p,
      elapsed: Number(p.elapsed),
      margin: sign * Number(p.home_margin) + 0,
      cum_ppa: sign * Number(p.home_cum_ppa) + 0,
      team_score: Number(isHome ? p.home_score : p.away_score),
      opp_score: Number(isHome ? p.away_score : p.home_score)
    }));
}

export function parsePlayers(json) {
  if (!json) return [];
  try {
    const players = JSON.parse(json);
    return Array.isArray(players) ? players : [];
  } catch {
    return [];
  }
}
```

`vignettes/explorer/plays.js`:

```js
// One game's plays from a season parquet over HTTP range requests (decision
// 0046). The hyparquet module is passed in, so node tests use a fake and
// never touch the network.

// Row ranges of the groups whose game_id min/max spans the game. Groups
// without statistics are always read.
export function pickRowGroups(metadata, gameId) {
  const picks = [];
  let start = 0;
  for (const rg of metadata.row_groups) {
    const n = Number(rg.num_rows);
    const col = rg.columns.find(c => (c.meta_data?.path_in_schema ?? []).join(".") === "game_id");
    const st = col?.meta_data?.statistics ?? {};
    const lo = Number(st.min_value ?? st.min);
    const hi = Number(st.max_value ?? st.max);
    if (!(gameId < lo || gameId > hi)) picks.push({rowStart: start, rowEnd: start + n});
    start += n;
  }
  return picks;
}

// Reads one game's rows. The file handle and metadata are cached per URL, so
// later games in the same season skip the footer fetch.
export async function readGamePlays(hp, url, gameId, cache) {
  if (!cache.has(url)) {
    const opened = (async () => {
      const file = await hp.asyncBufferFromUrl({url});
      const metadata = await hp.parquetMetadataAsync(file);
      return {file, metadata};
    })();
    cache.set(url, opened.catch(error => {
      cache.delete(url);
      throw error;
    }));
  }
  const {file, metadata} = await cache.get(url);
  const rows = [];
  for (const {rowStart, rowEnd} of pickRowGroups(metadata, gameId)) {
    const part = await hp.parquetReadObjects({file, metadata, rowStart, rowEnd});
    for (const r of part) if (Number(r.game_id) === gameId) rows.push(r);
  }
  return rows;
}
```

- [ ] **Step 3: Run, expect pass**

Run: `node --test vignettes/explorer/state.test.mjs vignettes/explorer/ui.test.mjs vignettes/explorer/teams.test.mjs vignettes/explorer/plays.test.mjs`
Expected: all pass. Also `Rscript -e 'devtools::test(filter = "explorer-js")'`
(it picks up every `*.test.mjs`).

- [ ] **Step 4: Commit**

```bash
git add vignettes/explorer/teams.js vignettes/explorer/teams.test.mjs vignettes/explorer/plays.js vignettes/explorer/plays.test.mjs
git commit -m "feat(explorer): Teams-tab helpers and range-read plays reader with node tests"
```

### Task 8: The Teams tab

**Files:**
- Modify: `vignettes/explorer.qmd`, `vignettes/explorer/explorer.css`

The tab stacks four levels top to bottom: **Conferences → Team → Season →
Game**. Choosing at one level updates everything below and scrolls to the
next level. Defaults: FBS landscape, Texas, the selected season, and the
latest game with play-by-play. Only the reader's own game pick goes into the
hash (`game=`); the default game is implied.

- [ ] **Step 1: Shared cells.** In `vignettes/explorer.qmd`:

(a) Extend the import cell:

```js
import {TABS, parseHash, toHash, resolveTeam} from "./explorer/state.js"
import {sourceLine, errorCard, loadOnce, escapeHtml} from "./explorer/ui.js"
import {formatRecord, teamGames, effectiveGame, landscapePanels, timelineFor, parsePlayers} from "./explorer/teams.js"
import {readGamePlays} from "./explorer/plays.js"
```

(b) In the setup cell (the one with `mutable retry = 0`), add after `tabCache`:

```js
mutable teamsRetry = 0
mutable focusConf = null
mutable scrubPlay = null
parquetCache = new Map()
async function fetchJson(path) {
  const response = await fetch(new URL(path, document.baseURI));
  if (!response.ok) throw new Error(`${response.status} ${path}`);
  return response.json();
}
```

(c) Add a new cell after the hash-state cell. It holds the two inputs that
have no visible control:

```{ojs}
//| echo: false
//| output: false
// The reader's game and player picks; set from taps, carried in the hash.
viewof game = Inputs.input(hashState.game)
viewof player = Inputs.input(hashState.player)
```

(d) Add a cell with the pick helpers (they reference the inputs, so they
live after them):

```{ojs}
//| echo: false
//| output: false
// A tap sets an input the way a reader would, then scrolls to the next level.
pick = {
  const set = (view, value) => {
    view.value = value;
    view.dispatchEvent(new Event("input", {bubbles: true}));
  };
  const scroll = id => document.getElementById(id)?.scrollIntoView({behavior: "smooth", block: "start"});
  return {
    team: id => { set(viewof team, id); scroll("teams-team"); },
    season: s => { set(viewof season, s); scroll("teams-season"); },
    game: id => { set(viewof game, id); scroll("teams-game"); },
    player: id => { set(viewof player, id); set(viewof tab, "players"); }
  };
}
```

(e) Add the season's team games (loaded on every tab: they validate the
hash's `game`, and a season is ~60 KB gzipped):

```{ojs}
//| echo: false
//| output: false
seasonGamesData = {
  teamsRetry;
  try {
    return {rows: await loadOnce(tabCache, `team_games_${season}`, () => fetchJson(`explorer-data/team_games_${season}.json`))};
  } catch (error) {
    return {error, rows: []};
  }
}
teamSeasonGames = teamGames(seasonGamesData.rows, team)
shownGame = effectiveGame(game, teamSeasonGames)
gameRow = teamSeasonGames.find(g => g.game_id === shownGame) ?? null
```

(f) Replace the hash-writer cell's body with:

```js
{
  // Only the reader's own game pick goes into the hash; the default game is implied.
  const gameKey = teamSeasonGames.some(g => g.game_id === game) ? game : null;
  const next = toHash({...hashState, tab, season, team, game: gameKey, player});
  if (next === location.hash) return;
  // Push only input-driven changes. A write that merely canonicalizes the
  // live URL replaces it, so Back never lands on a non-canonical entry.
  const cur = parseHash(location.hash, ready.meta);
  cur.team = resolveTeam(cur.team, ready.teams, ready.meta);
  if (cur.team === team && cur.season === season && !teamSeasonGames.some(g => g.game_id === cur.game)) cur.game = null;
  if (!location.hash || toHash(cur) === next) history.replaceState(null, "", next);
  else history.pushState(null, "", next);
}
```

- [ ] **Step 2: CSS** (append to `vignettes/explorer/explorer.css`)

```css
/* Teams tab (step 3). */
.explorer-panels { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 0.75rem; }
.explorer-panel { all: unset; display: block; cursor: pointer; border: 1px solid #e5e7eb; border-radius: 0.5rem; padding: 0.5rem; }
.explorer-panel:focus-visible { outline: 2px solid #2563eb; }
.explorer-panel h4 { margin: 0 0 0.25rem; font-size: 1rem; }
.explorer-chips { display: flex; flex-wrap: wrap; gap: 0.4rem; margin: 0.75rem 0; }
.explorer-chip {
  min-height: 44px; display: inline-flex; align-items: center; gap: 0.4rem;
  padding: 0.4rem 0.8rem; border: 1px solid #d1d5db; border-radius: 999px;
  background: #fff; font-size: 1rem; cursor: pointer;
}
.explorer-chip[aria-pressed="true"] { border-color: #111827; box-shadow: inset 0 0 0 2px #111827; }
.explorer-chip span { color: #4b5563; font-size: 0.9rem; }
.explorer-tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 0.5rem; margin: 0.75rem 0; }
.explorer-tile {
  min-height: 44px; display: flex; flex-direction: column; align-items: flex-start; gap: 0.15rem;
  padding: 0.5rem; border: 1px solid #d1d5db; border-left-width: 6px; border-radius: 0.4rem;
  background: #fff; font-size: 0.95rem; text-align: left; cursor: pointer;
}
.explorer-tile.explorer-W { border-left-color: #15803d; }
.explorer-tile.explorer-L { border-left-color: #b91c1c; }
.explorer-tile.explorer-T { border-left-color: #6b7280; }
.explorer-tile[aria-pressed="true"] { box-shadow: inset 0 0 0 2px #111827; }
.explorer-tile-week, .explorer-tile-elo { color: #4b5563; font-size: 0.85rem; }
.explorer-game svg { touch-action: pan-y; } /* horizontal drags scrub, vertical drags scroll */
.explorer-play p { margin: 0.2rem 0; }
.explorer-summary { font-size: 1rem; color: #374151; }
```

- [ ] **Step 3: Commit the shared changes** (the page still renders, because the
  old Teams section is untouched)

```bash
git add vignettes/explorer.qmd vignettes/explorer/explorer.css
git commit -m "feat(explorer): game and player inputs, season games, pick helpers"
```

- [ ] **Step 4: Replace the Teams section.** Replace everything from
  `::: {#tab-teams .explorer-tab hidden=""}` through its closing `:::` (just
  before `::: {#tab-players`) with the block below. The team select keeps its
  name and its comment.

````markdown
::: {#tab-teams .explorer-tab hidden=""}
## Teams

### Conferences {#teams-landscape}

```{ojs}
//| echo: false
viewof showFcs = Inputs.toggle({label: "Show FCS", value: false})
```

```{ojs}
//| echo: false
landscape = {
  const classification = showFcs ? "fcs" : "fbs";
  const panels = landscapePanels(ready.teamSeason, season, classification);
  const metric = classification === "fbs" ? "elo_end" : "win_pct";
  const yLabel = metric === "elo_end" ? "End-of-season Elo" : "Win share";
  const value = d => metric === "elo_end" ? `Elo ${d.elo_end}` : `${Math.round(d.win_pct * 100)}% wins`;
  const color = id => ready.teamById.get(id)?.color ?? "#6b7280";
  const name = id => ready.teamById.get(id)?.team ?? String(id);
  const focused = panels.find(p => p.conference === focusConf);
  if (!focused) {
    // Small multiples: the selected team's line in its color, the rest grey.
    const grid = html`<div class="explorer-panels"></div>`;
    for (const p of panels) {
      const fig = Plot.plot({
        height: 150, marginLeft: 44, style: {fontSize: "13px"},
        x: {label: null, tickFormat: String, ticks: 4},
        y: {label: null, ticks: 3},
        marks: [
          Plot.ruleX([season], {stroke: "#9ca3af", strokeDasharray: "3,3"}),
          Plot.line(p.rows, {
            x: "season", y: metric, z: "team_id",
            stroke: d => d.team_id === team ? color(team) : "#9ca3af",
            strokeWidth: d => d.team_id === team ? 3 : 1,
            strokeOpacity: d => d.team_id === team ? 1 : 0.5
          })
        ]
      });
      const card = html`<button type="button" class="explorer-panel" aria-label=${`Open ${p.conference}`}><h4>${p.conference}</h4>${fig}</button>`;
      card.onclick = () => { mutable focusConf = p.conference; };
      grid.append(card);
    }
    return grid;
  }
  // One conference, large: tap near a line (or a chip) to open that team.
  const fig = Plot.plot({
    height: 360, marginLeft: 56, style: {fontSize: "16px"},
    x: {label: "Season", tickFormat: String},
    y: {label: yLabel, grid: true},
    marks: [
      Plot.ruleX([season], {stroke: "#9ca3af", strokeDasharray: "4,4"}),
      Plot.line(focused.rows, {
        x: "season", y: metric, z: "team_id",
        stroke: d => color(d.team_id),
        strokeWidth: d => d.team_id === team ? 4 : 1.5,
        strokeOpacity: d => d.team_id === team ? 1 : 0.6
      }),
      Plot.dot(focused.rows, Plot.pointer({
        x: "season", y: metric, fill: d => color(d.team_id), r: 6,
        title: d => `${name(d.team_id)} ${d.season}: ${value(d)}, ${formatRecord(d)}`,
        tip: true
      }))
    ]
  });
  fig.addEventListener("click", () => { if (fig.value) pick.team(fig.value.team_id); });
  const back = html`<button type="button" class="explorer-chip">← All conferences</button>`;
  back.onclick = () => { mutable focusConf = null; };
  const chips = html`<div class="explorer-chips"></div>`;
  const now = focused.rows.filter(d => d.season === season).sort((a, b) => b[metric] - a[metric]);
  for (const d of now) {
    const t = ready.teamById.get(d.team_id);
    const chip = html`<button type="button" class="explorer-chip" aria-pressed=${String(d.team_id === team)}>${t?.logo ? html`<img src=${t.logo} alt="" width="24" height="24" loading="lazy">` : ""}${name(d.team_id)} <span>${formatRecord(d)}</span></button>`;
    chip.onclick = () => pick.team(d.team_id);
    chips.append(chip);
  }
  return html`<div>${back}<h4>${focused.conference} in ${season}</h4>${fig}${chips}</div>`;
}
```

::: {.column-margin}
Each line is one team's rating at the end of every season. Membership is as
of the selected season, so a team that changed conference keeps its whole
history on one line. FCS teams have no Elo rating; their panels show **win
share**, $(W + T/2) / G$ over the season's $G$ games.
:::

```{ojs}
//| echo: false
asNode(sourceLine(ready.meta.sources.teams_landscape))
```

### Team {#teams-team}

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
teamView = {
  const info = ready.teamById.get(team);
  const rows = ready.teamSeason.filter(d => d.team_id === team);
  const elo = rows.filter(d => d.elo_end !== null);
  const out = html`<div></div>`;
  if (elo.length) {
    const fig = Plot.plot({
      height: 300, marginLeft: 56, style: {fontSize: "16px"},
      x: {label: "Season", tickFormat: String},
      y: {label: "End-of-season Elo", grid: true},
      marks: [
        Plot.ruleX([season], {stroke: "#9ca3af", strokeDasharray: "4,4"}),
        Plot.line(elo, {x: "season", y: "elo_end", stroke: info.color, strokeWidth: 3}),
        Plot.dot(elo, Plot.pointerX({
          x: "season", y: "elo_end", fill: info.color, r: 7,
          title: d => `${d.season}: Elo ${d.elo_end}, record ${formatRecord(d)}`,
          tip: true
        }))
      ]
    });
    fig.addEventListener("click", () => { if (fig.value) pick.season(fig.value.season); });
    out.append(fig);
  } else {
    out.append(asNode(`<div class="explorer-card">${escapeHtml(info.team)} has no Elo rating: CFBD rates FBS teams only.</div>`));
  }
  // Wins and losses by season; tap a season to open its games.
  const bars = rows.flatMap(d => [
    {season: d.season, outcome: "Wins", n: d.wins},
    {season: d.season, outcome: "Losses", n: d.losses},
    {season: d.season, outcome: "Ties", n: d.ties}
  ]).filter(d => d.n > 0);
  const wl = Plot.plot({
    height: 200, marginLeft: 40, style: {fontSize: "16px"},
    x: {label: "Season", type: "band", tickFormat: d => d % 4 === 2 ? String(d) : ""},
    y: {label: "Games", grid: true},
    color: {domain: ["Wins", "Losses", "Ties"], range: [info.color, "#9ca3af", "#d1d5db"], legend: true},
    marks: [
      Plot.barY(bars, {x: "season", y: "n", fill: "outcome", fillOpacity: d => d.season === season ? 1 : 0.55}),
      Plot.tip(rows, Plot.pointerX({x: "season", y: "games", title: d => `${d.season}: ${formatRecord(d)}`}))
    ]
  });
  wl.addEventListener("click", () => { if (wl.value) pick.season(wl.value.season); });
  out.append(wl);
  return out;
}
```

::: {.column-margin}
**End-of-season Elo** is the team's CFBD Elo rating after its last rated game
of the season. A rating gap of $D$ points gives the higher-rated team an
expected win probability of

$$E = \frac{1}{1 + 10^{-D/400}}$$

so a 100-point edge is about a 64% favorite. Tap a season in either chart to
open its games.
:::

```{ojs}
//| echo: false
asNode(sourceLine(ready.meta.sources.team_view))
```

### Season {#teams-season}

```{ojs}
//| echo: false
seasonStrip = {
  const info = ready.teamById.get(team);
  if (seasonGamesData.error) {
    const card = asNode(errorCard(`the ${season} games`));
    card.querySelector("button").onclick = () => { mutable teamsRetry = teamsRetry + 1; };
    return card;
  }
  if (!teamSeasonGames.length) {
    return asNode(`<div class="explorer-card">${escapeHtml(info.team)} has no completed games in ${season} yet.</div>`);
  }
  const rated = teamSeasonGames.map((g, i) => ({...g, i: i + 1})).filter(g => g.elo_post !== null);
  const out = html`<div><h4>${info.team} in ${season}</h4></div>`;
  if (rated.length) {
    out.append(Plot.plot({
      height: 130, marginLeft: 52, style: {fontSize: "14px"},
      x: {label: "Game", ticks: Math.min(rated.length, 8)},
      y: {label: "Elo", grid: true},
      marks: [
        Plot.line(rated, {x: "i", y: "elo_post", stroke: info.color, strokeWidth: 2}),
        Plot.dot(rated, {
          x: "i", y: "elo_post", stroke: info.color,
          fill: d => d.game_id === shownGame ? info.color : "white",
          r: d => d.game_id === shownGame ? 7 : 4
        })
      ]
    }));
  }
  const tiles = html`<div class="explorer-tiles"></div>`;
  for (const g of teamSeasonGames) {
    const opp = ready.teamById.get(g.opp_id);
    const where = g.site === "home" ? "vs" : g.site === "away" ? "at" : "vs (neutral)";
    const label = g.season_type === "regular" ? `Week ${g.week}` : "Postseason";
    const delta = g.elo_delta === null ? "" : `Elo ${g.elo_delta > 0 ? "+" : ""}${g.elo_delta}`;
    const tile = html`<button type="button" class=${`explorer-tile explorer-${g.result}`} aria-pressed=${String(g.game_id === shownGame)}>
      <span class="explorer-tile-week">${label}</span>
      ${opp?.logo ? html`<img src=${opp.logo} alt="" width="32" height="32" loading="lazy">` : ""}
      <span>${where} ${opp?.team ?? g.opp_name}</span>
      <strong>${g.result} ${g.points}-${g.opp_points}</strong>
      <span class="explorer-tile-elo">${delta}</span>
    </button>`;
    tile.onclick = () => pick.game(g.game_id);
    tiles.append(tile);
  }
  out.append(tiles);
  return out;
}
```

::: {.column-margin}
**Elo change** is the rating after the game minus the rating before it. The
mini line shows the rating after each game; the filled dot is the game shown
below.
:::

```{ojs}
//| echo: false
asNode(sourceLine(ready.meta.sources.team_season))
```

### Game {#teams-game}

```{ojs}
//| echo: false
//| output: false
gamePlaysData = {
  if (!gameRow || !gameRow.has_plays) return {rows: []};
  teamsRetry;
  try {
    const hp = await loadOnce(tabCache, "hyparquet", () => import("https://cdn.jsdelivr.net/npm/hyparquet@1/+esm"));
    const url = new URL(`explorer-data/plays_${season}.parquet`, document.baseURI).href;
    return {rows: await readGamePlays(hp, url, gameRow.game_id, parquetCache)};
  } catch (error) {
    return {error, rows: []};
  }
}
timeline = gameRow ? timelineFor(gamePlaysData.rows, gameRow.home) : []
```

```{ojs}
//| echo: false
gameView = {
  if (!gameRow) return document.createComment("no game");
  const info = ready.teamById.get(team);
  const opp = ready.teamById.get(gameRow.opp_id);
  const oppName = opp?.team ?? gameRow.opp_name;
  const pct = p => p === null || p === undefined ? "not rated" : `${Math.round(p * 100)}%`;
  const out = html`<div class="explorer-game">
    <h4>${info.team} ${gameRow.points}, ${oppName} ${gameRow.opp_points}</h4>
    <p class="explorer-summary">Elo win chance before kickoff: <strong>${pct(gameRow.wp_pre)}</strong> · CFBD win probability after the game: <strong>${pct(gameRow.wp_post)}</strong></p>
  </div>`;
  if (gamePlaysData.error) {
    const card = asNode(errorCard("this game's plays"));
    card.querySelector("button").onclick = () => { mutable teamsRetry = teamsRetry + 1; };
    out.append(card);
    return out;
  }
  if (!timeline.length) {
    out.append(asNode(`<div class="explorer-card">No play-by-play for this game.</div>`));
    return out;
  }
  const oppColor = opp?.color ?? "#6b7280";
  const x = {label: null, ticks: [0, 900, 1800, 2700, 3600], tickFormat: s => ["Q1", "Q2", "Q3", "Q4", "OT"][s / 900] ?? ""};
  const label = info.abbreviation ?? info.team;
  const margin = Plot.plot({
    height: 240, marginLeft: 52, style: {fontSize: "16px"}, x,
    y: {label: `${label} lead`, grid: true},
    marks: [
      Plot.ruleY([0], {stroke: "#9ca3af"}),
      Plot.line(timeline, {x: "elapsed", y: "margin", curve: "step-after", stroke: info.color, strokeWidth: 3}),
      Plot.dot(timeline.filter(d => d.scoring), {
        x: "elapsed", y: "margin", r: 5,
        fill: d => d.offense_id === team ? info.color : oppColor
      }),
      Plot.dot(timeline.filter(d => d.turnover), {
        x: "elapsed", y: "margin", symbol: "times", r: 7, stroke: "#b91c1c", strokeWidth: 2
      }),
      Plot.ruleX(timeline, Plot.pointerX({x: "elapsed", stroke: "#111827"}))
    ]
  });
  const ppa = Plot.plot({
    height: 200, marginLeft: 52, style: {fontSize: "16px"}, x,
    y: {label: "Cumulative PPA edge", grid: true},
    marks: [
      Plot.ruleY([0], {stroke: "#9ca3af"}),
      Plot.line(timeline, {x: "elapsed", y: "cum_ppa", stroke: info.color, strokeWidth: 2}),
      Plot.ruleX(timeline, Plot.pointerX({x: "elapsed", stroke: "#111827"}))
    ]
  });
  for (const fig of [margin, ppa]) {
    fig.addEventListener("input", () => { if (fig.value) mutable scrubPlay = fig.value; });
  }
  out.append(margin, ppa);
  return out;
}
```

```{ojs}
//| echo: false
playCard = {
  if (!timeline.length) return document.createComment("no plays");
  const p = scrubPlay && timeline.includes(scrubPlay) ? scrubPlay : timeline[0];
  const info = ready.teamById.get(team);
  const opp = ready.teamById.get(gameRow.opp_id);
  const ord = ["", "1st", "2nd", "3rd", "4th"];
  const when = p.period > 4 ? p.clock : `Q${p.period} ${p.clock ?? ""}`;
  const downs = p.down ? ` · ${ord[p.down] ?? p.down} & ${p.distance}` : "";
  const field = p.yards_to_goal !== null && p.yards_to_goal !== undefined ? ` · ${p.yards_to_goal} yards to go` : "";
  const card = html`<div class="explorer-card explorer-play" aria-live="polite">
    <p><strong>${when}</strong>${downs}${field}</p>
    <p>${info.abbreviation ?? info.team} ${p.team_score}, ${opp?.abbreviation ?? gameRow.opp_name} ${p.opp_score}</p>
    <p>${p.play_text ?? p.play_type}</p>
  </div>`;
  const players = parsePlayers(p.players);
  if (players.length) {
    const chips = html`<div class="explorer-chips"></div>`;
    for (const a of players) {
      const chip = html`<button type="button" class="explorer-chip">${a.name} <span>${a.stat}</span></button>`;
      chip.onclick = () => pick.player(a.id);
      chips.append(chip);
    }
    card.append(chips);
  }
  return card;
}
```

::: {.column-margin}
**Game clock** runs left to right as elapsed seconds: $(q - 1) \times 900 +
(900 - r)$ for quarter $q$ with $r$ seconds left. Each overtime period gets a
300-second slot.

**Lead** is the selected team's score minus its opponent's after each play.
Filled dots are scoring plays and red crosses are turnovers.

**PPA** (predicted points added) is how much a play changed the offense's
expected points. The **cumulative PPA edge** adds the team's offensive PPA
and subtracts the opponent's, play by play, so it rises while the team is
outplaying its opponent even when the score doesn't move.

Drag across either chart to read any play.
:::

```{ojs}
//| echo: false
asNode(sourceLine(ready.meta.sources.game_timeline))
```
:::
````

- [ ] **Step 5: Commit**

```bash
git add vignettes/explorer.qmd
git commit -m "feat(explorer): Teams tab with landscape, team, season strip and game timeline"
```

### Task 9: Render and verify on a phone viewport

Follow `plans/explorer-shell-impl.md` Task 9 Steps 1–2 (full altdoc render;
start the node server from that plan's script on 8080). Then, with Playwright
at 390×844, check each item and record PASS/FAIL with evidence:

1. Load `explorer.html` with no hash. There are no console errors apart from
   the favicon 404. The FBS panels render with Texas highlighted, the team
   view shows Texas, the season strip shows the selected season's games, and
   the game view shows the latest game with plays (timeline, both charts, and
   a play card).
2. Tap the SEC panel and the focused view opens. Tap the Alabama chip and the
   Team section shows Alabama and scrolls into view. The hash has `team=333`.
3. Tap a season bar (e.g. 2020) and the season strip shows 2020 games. The
   hash has `season=2020` and no `game=`.
4. Tap a game tile. The game view and mini Elo dot update, and the hash has
   `game=<id>`. Back returns to the previous game.
5. Drag across the margin chart (`browser_drag` from left to right). The play
   card text changes. Check `scrubPlay` by comparing card text before and
   after.
6. A 2026 game: the play card lists player chips (2026 has `play_stats`).
   Tapping one switches to the Players tab with `player=<id>` in the hash.
7. A game without plays: pick an FCS team (Montana, 149) and a season with a
   D-II opponent if available, or any tile whose game has no plays. The card
   says "No play-by-play for this game".
8. The FCS toggle: panels switch to win share, and the margin note explains
   it.
9. Network: opening a game fetches `plays_<season>.parquet` with 206
   responses totalling ≤ 1 MB the first time in a season, and ≤ 300 KB for a
   second game in the same season. hyparquet loads once.
10. Tap targets: every chip and tile is ≥ 44px tall
    (`[...document.querySelectorAll('.explorer-chip, .explorer-tile')].map(e => e.getBoundingClientRect().height)`).
11. The step-2 checks still pass: the default hash
    (`#tab=teams&season=2026&team=251&pos=QB`), Back from another page, and
    the error card for a missing `teams.json`.

Fix failures in the Task 7–8 files, keeping node tests green. Commit each fix
as `fix(explorer): <what>`. Commit any `_quarto/_freeze/` change the render
makes to tracked pages. Kill the server.

### Task 10: Spec, NEWS, PR

- [ ] `plans/explorer.md`: tick build-order step 3 (`[x] ... (done <date>)`),
  and in "Data assets" rename `games_<season>.json` to `team_games_<season>.json`
  (one row per team per game, with each team's side). Note that the FCS
  landscape uses win share, and that the game view defaults to the latest
  game with plays.
- [ ] `NEWS.md`: under the development heading, add a bullet:

```markdown
- The Explorer's **Teams** tab: conference landscapes of every team's
  end-of-season Elo (FCS by win share), each team's rating and record by
  season, its games week by week, and a play-by-play timeline of any game
  with the lead and the cumulative PPA edge you can scrub through (#70).
```

- [ ] Run `air format . && Rscript -e 'devtools::test()'` and the four node
  test files. Commit, push, and open the PR with the `gh` R package
  (controller writes the description from the task reports).
