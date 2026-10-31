# Conferences & Teams (team tables + Post 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared `team_season` and `team_draft` derived tables and publish Post 1 (the conference/team landscape and data coverage) of the series specified in `plans/conferences-teams.md`.

**Architecture:** Pure functions in a new `R/teams.R` (position grouping, team win-loss record, team-season table, per-player college exit cohort, team × final-season × position-group draft table), each unit-tested, contract-checked by pointblank, wired into `_targets.R` as derived tables (decision 0021: bundled into DuckDB, not published parquet), documented in `inst/dict/`. Post 1 reads the DuckDB bundle. Posts 2 and 3 get their own implementation plans after Post 1 lands.

**Tech Stack:** R, dplyr/tidyr, targets, pointblank, testthat, DuckDB, Quarto, ggplot2 + ggiraph, knitr::kable.

**Spec:** `plans/conferences-teams.md`. Read it and AGENTS.md first.

---

## Facts measured while planning (2026-10-31)

- Local `_targets` store is **stale**: `games` and `reused` targets are not
  built. Task 0 brings it current.
- Roster has **282** duplicated `(playerId, season)` rows (one id on two teams
  in one season). Tie-break deterministically (alphabetical team) and report.
- Attribution prototype (final roster season before draft year, reused ids
  excluded, one pick per player = earliest year): classes 2014+ attribute
  **3,129 of 3,307** id-bearing picks (**94.6%**); 3,751 credit seasons are
  draft year − 1, 24 are − 2/− 3.
- 3,610 UDFA players in `outcomes`.
- Roster positions observed: `? ATH C CB DB DE DL DT EDGE FB G ILB KR LB LS NT
  OL OLB OT P PK PR QB RB S TE WR` (plus NA). `?`, `ATH`, NA → not recorded.
- Games: 45 ties; 1,178 not completed (2026 in progress); one team-season has
  two conferences in `games`; games conference names equal `ps_tier`
  conference names for all 3,893 shared team-seasons; ~359 games
  conference-seasons (Division II/III, Ivy, NA) are absent from `tiers`, so
  non-FBS teams fall back to tier 1.
- `coaches` carries `srs`, `sp_overall` per `(school, season)`; duplicate
  rows exist for mid-season changes (take the first non-NA).

## File map

- Create `R/teams.R`: `position_group()`, `team_record()`,
  `build_team_season()`, `exit_cohort()`, `build_team_draft()`.
- Create `tests/testthat/test-teams.R`: unit tests for the above.
- Modify `R/contracts.R`: add `contract_team_season()`, `contract_team_draft()`.
- Modify `tests/testthat/test-contracts.R`: contract tests.
- Modify `_targets.R`: targets, `ok_*`, gate, audit steps, DuckDB list.
- Create `inst/dict/team_season.yml`, `inst/dict/team_draft.yml`.
- Modify `tests/testthat/test-dict-derived.R`, `inst/data-model.md`.
- Create `decisions/0033-team-draft-attribution.md`.
- Create `vignettes/2026-10-31-conferences-landscape.qmd` (Post 1).
- Modify `NEWS.md`.

---

### Task 0: Bring the local pipeline current

- [ ] **Step 1:** Run `Rscript -e 'targets::tar_make()'` (track mode; no API key needed). Expected: completes, `contract_gate` passes.
- [ ] **Step 2:** Verify: `Rscript -e 'targets::tar_read(reused) |> length(); nrow(targets::tar_read(games))'` prints ~131 and 37072.
- [ ] **Step 3:** If tar_make fails, stop and use superpowers:systematic-debugging; do not proceed on a stale store.

### Task 1: `position_group()`

Replaces the three hand-copied maps in the 2026-10-24 and 2026-10-30 posts
(those posts are frozen; leave them as is).

**Files:** Create `R/teams.R`, `tests/testthat/test-teams.R`.

- [ ] **Step 1: Write the failing test**

```r
test_that("position_group maps every roster code to a reader label", {
  codes <- c(
    "QB", "RB", "FB", "WR", "TE", "T", "G", "C", "OL", "OT",
    "DL", "DE", "DT", "NT", "EDGE", "LB", "ILB", "OLB",
    "DB", "S", "CB", "PK", "P", "LS", "PR", "KR", "?", "ATH", NA
  )
  out <- position_group(codes)
  expect_type(out, "character")
  expect_false(anyNA(out))
  expect_equal(out[codes %in% c("T", "G", "C", "OL", "OT")], rep("Offensive line", 5))
  expect_equal(out[codes %in% c("FB")], "Running back")
  expect_equal(out[codes %in% c("KR", "PR")], rep("Special teams", 2))
  expect_equal(out[is.na(codes) | codes %in% c("?", "ATH")], rep("Position not recorded", 3))
  expect_setequal(unique(out), c(position_group_levels(), "Position not recorded"))
})
```

- [ ] **Step 2:** Run `Rscript -e 'devtools::test(filter = "teams")'`. Expected: FAIL, `could not find function "position_group"`.

- [ ] **Step 3: Implement in `R/teams.R`**

```r
# Team- and conference-grain derived tables (plans/conferences-teams.md).
# A draftee is credited to the team of their final roster season before the
# draft (decision 0033); rates divide by players whose college career ended
# at that team, so offensive linemen (who have almost no stat lines) count.

#' Position-group labels, in display order
#'
#' @return A character vector of the nine reader-facing position groups.
#' @export
position_group_levels <- function() {
  c(
    "Quarterback", "Running back", "Receiver", "Tight end", "Offensive line",
    "Defensive line", "Linebacker", "Defensive back", "Special teams"
  )
}

#' Map roster position codes to reader-facing position groups
#'
#' One map shared by every post and table, so numerators and denominators
#' group positions identically. Unknown codes (`?`, `ATH`, `NA`, anything
#' new) become "Position not recorded" rather than being dropped.
#'
#' @param position Character vector of CFBD roster position codes.
#' @return Character vector of group labels (see [position_group_levels()]).
#' @export
position_group <- function(position) {
  map <- c(
    QB = "Quarterback", RB = "Running back", FB = "Running back",
    WR = "Receiver", TE = "Tight end",
    T = "Offensive line", G = "Offensive line", C = "Offensive line",
    OL = "Offensive line", OT = "Offensive line",
    DL = "Defensive line", DE = "Defensive line", DT = "Defensive line",
    NT = "Defensive line", EDGE = "Defensive line",
    LB = "Linebacker", ILB = "Linebacker", OLB = "Linebacker",
    DB = "Defensive back", S = "Defensive back", CB = "Defensive back",
    PK = "Special teams", P = "Special teams", LS = "Special teams",
    PR = "Special teams", KR = "Special teams"
  )
  out <- unname(map[position])
  out[is.na(out)] <- "Position not recorded"
  out
}
```

- [ ] **Step 4:** Run the test. Expected: PASS.
- [ ] **Step 5:** Commit: `git add R/teams.R tests/testthat/test-teams.R && git commit -m "feat(teams): shared position_group map"`

### Task 2: `team_record()`

**Files:** Modify `R/teams.R`, `tests/testthat/test-teams.R`.

- [ ] **Step 1: Write the failing test**

```r
test_that("team_record counts wins, losses, ties from completed games only", {
  games <- tibble::tibble(
    season = 2019L,
    completed = c(TRUE, TRUE, TRUE, FALSE),
    homeTeam = c("LSU", "Alabama", "LSU", "LSU"),
    homeConference = c("SEC", "SEC", "SEC", "SEC"),
    homeClassification = "fbs",
    homePoints = c(42L, 41L, 20L, NA),
    awayTeam = c("Alabama", "Troy", "Troy", "Troy"),
    awayConference = c("SEC", "Sun Belt", "Sun Belt", "Sun Belt"),
    awayClassification = "fbs",
    awayPoints = c(25L, 46L, 20L, NA)
  )
  rec <- team_record(games)
  lsu <- rec[rec$team == "LSU", ]
  expect_equal(c(lsu$games_played, lsu$wins, lsu$losses, lsu$ties), c(2L, 1L, 0L, 1L))
  expect_equal(lsu$win_pct, 0.75)
  expect_equal(lsu$conference, "SEC")
  troy <- rec[rec$team == "Troy", ]
  expect_equal(c(troy$wins, troy$losses, troy$ties), c(1L, 0L, 1L))
  expect_equal(nrow(rec), 3L)
  expect_false(anyDuplicated(rec[c("team", "season")]) > 0)
})

test_that("team_record gives NA win_pct when a team has no completed games", {
  games <- tibble::tibble(
    season = 2020L, completed = FALSE,
    homeTeam = "A", homeConference = "X", homeClassification = "fcs", homePoints = NA_integer_,
    awayTeam = "B", awayConference = "X", awayClassification = "fcs", awayPoints = NA_integer_
  )
  rec <- team_record(games)
  expect_equal(rec$games_played, c(0L, 0L))
  expect_true(all(is.na(rec$win_pct)))
})
```

- [ ] **Step 2:** Run tests. Expected: FAIL, `could not find function "team_record"`.

- [ ] **Step 3: Implement**

```r
# Most frequent non-NA value (ties broken alphabetically), for the one
# team-season listed under two conferences in games.
mode_chr <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) return(NA_character_)
  tab <- table(x)
  names(tab)[tab == max(tab)][1L]
}

#' Season win-loss record for every team in the games table
#'
#' Stacks home and away sides so every team that appears in `games` (all
#' divisions) gets one row per season. Conference and classification come
#' from every listed game; the record counts completed games with scores
#' only, so an in-progress season has a partial record. A tie counts as half
#' a win in `win_pct`.
#'
#' @param games Cleaned games ([clean_games()]).
#' @return One row per `(season, team)`: `conference`, `classification`,
#'   `games_played`, `wins`, `losses`, `ties`, `win_pct`.
#' @export
team_record <- function(games) {
  side <- function(team, conf, class, pf, pa) {
    tibble::tibble(
      season = games$season,
      team = games[[team]],
      conference = games[[conf]],
      classification = games[[class]],
      done = games$completed & !is.na(games[[pf]]) & !is.na(games[[pa]]),
      pf = games[[pf]],
      pa = games[[pa]]
    )
  }
  dplyr::bind_rows(
    side("homeTeam", "homeConference", "homeClassification", "homePoints", "awayPoints"),
    side("awayTeam", "awayConference", "awayClassification", "awayPoints", "homePoints")
  ) |>
    dplyr::group_by(.data$season, .data$team) |>
    dplyr::summarise(
      conference = mode_chr(.data$conference),
      classification = mode_chr(.data$classification),
      games_played = sum(.data$done),
      wins = sum(.data$done & .data$pf > .data$pa),
      losses = sum(.data$done & .data$pf < .data$pa),
      ties = sum(.data$done & .data$pf == .data$pa),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      dplyr::across(c("games_played", "wins", "losses", "ties"), as.integer),
      win_pct = dplyr::if_else(
        .data$games_played > 0L,
        (.data$wins + 0.5 * .data$ties) / .data$games_played,
        NA_real_
      )
    )
}
```

- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -am "feat(teams): team_record from games"`

### Task 3: `build_team_season()`

**Files:** Modify `R/teams.R`, `tests/testthat/test-teams.R`.

- [ ] **Step 1: Write the failing test**

```r
team_fixture <- function() {
  list(
    games = tibble::tibble(
      season = 2019L, completed = TRUE,
      homeTeam = c("LSU", "Montana"), homeConference = c("SEC", "Big Sky"),
      homeClassification = c("fbs", "fcs"), homePoints = c(42L, 30L),
      awayTeam = c("Alabama", "Div2 U"), awayConference = c("SEC", "GLIAC"),
      awayClassification = c("fbs", "ii"), awayPoints = c(25L, 10L)
    ),
    roster = tibble::tibble(
      playerId = c("1", "2", "3", "4"), season = 2019L,
      team = c("LSU", "LSU", "Alabama", "Tulane"), position = "QB"
    ),
    tiers = tibble::tibble(
      season = 2019L, conference = c("SEC", "Big Sky"),
      tier = c(3L, 1L), tier_label = c("Power", "FCS and below")
    ),
    player_season = tibble::tibble(playerId = "1", season = 2019L, team = "LSU"),
    coaches = tibble::tibble(
      school = c("LSU", "LSU"), season = 2019L,
      srs = c(NA, 34.2), sp_overall = c(NA, 30.1)
    )
  )
}

test_that("build_team_season unions games and roster team-seasons", {
  f <- team_fixture()
  ts <- build_team_season(f$roster, f$games, f$tiers, f$player_season, f$coaches)
  expect_setequal(ts$team, c("LSU", "Alabama", "Montana", "Div2 U", "Tulane"))
  expect_false(anyDuplicated(ts[c("team", "season")]) > 0)
  lsu <- ts[ts$team == "LSU", ]
  expect_equal(c(lsu$n_roster, lsu$n_stat_players), c(2L, 1L))
  expect_true(lsu$has_stat_lines)
  expect_equal(c(lsu$srs, lsu$sp_overall), c(34.2, 30.1))
  expect_equal(lsu$tier_label, "Power")
  # Division II team absent from tiers falls back to tier 1.
  expect_equal(ts$tier[ts$team == "Div2 U"], 1L)
  # Roster-only team (no games) keeps its row with zero games, NA tier.
  tul <- ts[ts$team == "Tulane", ]
  expect_equal(tul$games_played, 0L)
  expect_true(is.na(tul$tier))
  expect_equal(ts$n_roster[ts$team == "Montana"], 0L)
})
```

- [ ] **Step 2:** Run tests. Expected: FAIL, function not found.

- [ ] **Step 3: Implement**

```r
#' Build the team-season table
#'
#' One row per team per season across every division: conference and tier,
#' win-loss record ([team_record()]), FBS ratings (SRS, SP+ from the coaches
#' table; NA elsewhere), roster size, and how many players carry a stat line.
#' The universe is every team in `games` plus any roster team without games,
#' so the landscape counts teams that played, not only teams with stats.
#' Conferences missing from the tier lookup (Division II/III and others that
#' never appear in player stats) fall back to tier 1 when the team is not FBS.
#'
#' @param roster Cleaned roster.
#' @param games Cleaned games.
#' @param tiers Conference-tier lookup.
#' @param player_season Player-season table ([build_player_season()]).
#' @param coaches Cleaned coaches.
#' @return One row per `(team, season)`.
#' @export
build_team_season <- function(roster, games, tiers, player_season, coaches) {
  tier_levels <- conference_tier_levels()
  ros <- roster |>
    dplyr::filter(!is.na(.data$team)) |>
    dplyr::distinct(.data$season, .data$team, .data$playerId) |>
    dplyr::count(.data$season, .data$team, name = "n_roster")
  stat <- player_season |>
    dplyr::distinct(.data$season, .data$team, .data$playerId) |>
    dplyr::count(.data$season, .data$team, name = "n_stat_players")
  # Mid-season coaching changes duplicate (school, season); ratings are team
  # properties, so take the first non-NA.
  rating <- coaches |>
    dplyr::group_by(team = .data$school, .data$season) |>
    dplyr::summarise(
      srs = dplyr::first(stats::na.omit(.data$srs), default = NA_real_),
      sp_overall = dplyr::first(stats::na.omit(.data$sp_overall), default = NA_real_),
      .groups = "drop"
    )
  team_record(games) |>
    dplyr::full_join(ros, by = c("season", "team")) |>
    dplyr::left_join(stat, by = c("season", "team")) |>
    dplyr::left_join(rating, by = c("season", "team")) |>
    dplyr::left_join(
      dplyr::select(tiers, "season", "conference", "tier"),
      by = c("season", "conference")
    ) |>
    dplyr::mutate(
      dplyr::across(
        c("games_played", "wins", "losses", "ties", "n_roster", "n_stat_players"),
        \(x) dplyr::coalesce(as.integer(x), 0L)
      ),
      has_stat_lines = .data$n_stat_players > 0L,
      tier = dplyr::if_else(
        is.na(.data$tier) & !is.na(.data$classification) & .data$classification != "fbs",
        1L,
        .data$tier
      ),
      tier_label = names(tier_levels)[match(.data$tier, tier_levels)]
    ) |>
    dplyr::select(
      "team", "season", "conference", "classification", "tier", "tier_label",
      "games_played", "wins", "losses", "ties", "win_pct", "srs", "sp_overall",
      "n_roster", "n_stat_players", "has_stat_lines"
    ) |>
    dplyr::arrange(.data$season, .data$team)
}
```

- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -am "feat(teams): build_team_season"`

### Task 4: `exit_cohort()`

Each player's college exit: the team of their final roster season before the
draft (drafted) or their final roster season (undrafted), the draft class it
feeds, and whether they were drafted / signed as a UDFA.

**Files:** Modify `R/teams.R`, `tests/testthat/test-teams.R`.

- [ ] **Step 1: Write the failing test**

```r
test_that("exit_cohort credits the last pre-draft roster team", {
  roster <- tibble::tibble(
    playerId = c("1", "1", "1", "2", "2", "3", "4", "4", "4", "5", "5"),
    season = c(2017L, 2018L, 2019L, 2018L, 2019L, 2021L, 2015L, 2016L, 2017L, 2019L, 2019L),
    team = c("Ohio State", "LSU", "LSU", "Troy", "Troy", "Troy", "Tulane", "Tulane", "Tulane", "Zed", "Alpha"),
    position = c("QB", "QB", "QB", "WR", "WR", "OL", "OT", "OT", "OT", "S", "CB")
  )
  picks <- tibble::tibble(
    playerId = c("1", "1", NA), year = c(2020L, 2021L, 2020L), round = c(1L, 2L, 3L)
  )
  out <- exit_cohort(roster, picks, udfa_ids = "4", reused = character(), last_roster_season = 2021L)

  p1 <- out[out$playerId == "1", ]
  expect_equal(p1$team, "LSU")
  expect_equal(p1$last_season, 2019L)
  expect_equal(p1$draft_class, 2020L)
  expect_true(p1$drafted && p1$eligible)
  expect_equal(p1$draft_round, 1L) # earliest pick wins (decision 0011)
  expect_equal(p1$position_group, "Quarterback")

  # Undrafted, 2 seasons, not UDFA: an exit but not eligible.
  p2 <- out[out$playerId == "2", ]
  expect_equal(p2$draft_class, 2020L)
  expect_false(p2$eligible)
  # Still on the latest roster and undrafted: censored, excluded.
  expect_false("3" %in% out$playerId)
  # UDFA lineman with 3 seasons.
  p4 <- out[out$playerId == "4", ]
  expect_true(p4$udfa && p4$eligible && !p4$drafted)
  expect_equal(p4$position_group, "Offensive line")
  # Same-season duplicate resolves to the alphabetical team.
  expect_equal(out$team[out$playerId == "5"], "Alpha")
  expect_false(anyDuplicated(out$playerId) > 0)
})

test_that("exit_cohort drops reused ids", {
  roster <- tibble::tibble(playerId = "9", season = 2015L, team = "A", position = "QB")
  out <- exit_cohort(roster, picks = tibble::tibble(playerId = character(), year = integer(), round = integer()),
                     udfa_ids = character(), reused = "9", last_roster_season = 2020L)
  expect_equal(nrow(out), 0L)
})
```

- [ ] **Step 2:** Run tests. Expected: FAIL, function not found.

- [ ] **Step 3: Implement**

```r
#' Each player's college exit: the team that gets credit and the outcome
#'
#' A drafted player is credited to the team of their final roster season
#' before the draft year (one pick per player, the earliest, decision 0011);
#' an undrafted player to their final roster season, feeding the next draft
#' class. Undrafted players still on the latest roster are excluded (their
#' outcome is not yet known). "Eligible" is a roster-based proxy for the NFL's
#' three-years-out-of-high-school rule: three or more roster seasons, or
#' drafted, or signed as a UDFA.
#'
#' @param roster Cleaned roster with `playerId`, `season`, `team`, `position`.
#' @param picks Cleaned picks with `playerId`, `year`, `round`.
#' @param udfa_ids Character vector of player ids who signed as undrafted
#'   free agents (from `outcomes`).
#' @param reused Reused athlete ids to exclude ([reused_ids()]).
#' @param last_roster_season Latest roster season in the data.
#' @return One row per player: `playerId`, `team`, `last_season`,
#'   `first_season`, `seasons`, `position`, `position_group`, `draft_class`,
#'   `drafted`, `draft_round`, `udfa`, `eligible`.
#' @export
exit_cohort <- function(
  roster,
  picks,
  udfa_ids,
  reused,
  last_roster_season = max(roster$season)
) {
  pk <- picks |>
    dplyr::filter(!is.na(.data$playerId), !.data$playerId %in% reused) |>
    dplyr::group_by(.data$playerId) |>
    dplyr::slice_min(.data$year, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select("playerId", draft_year = "year", draft_round = "round")
  roster |>
    dplyr::filter(!.data$playerId %in% reused, !is.na(.data$team)) |>
    # One team per player-season; alphabetical tie-break for the rare
    # same-season duplicate.
    dplyr::arrange(.data$playerId, .data$season, .data$team) |>
    dplyr::distinct(.data$playerId, .data$season, .keep_all = TRUE) |>
    dplyr::left_join(pk, by = "playerId") |>
    dplyr::filter(is.na(.data$draft_year) | .data$season < .data$draft_year) |>
    dplyr::group_by(.data$playerId) |>
    dplyr::summarise(
      team = .data$team[which.max(.data$season)],
      position = .data$position[which.max(.data$season)],
      first_season = min(.data$season),
      last_season = max(.data$season),
      seasons = dplyr::n_distinct(.data$season),
      draft_year = dplyr::first(.data$draft_year),
      draft_round = dplyr::first(.data$draft_round),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      drafted = !is.na(.data$draft_year),
      udfa = !.data$drafted & .data$playerId %in% udfa_ids,
      draft_class = dplyr::if_else(.data$drafted, .data$draft_year, .data$last_season + 1L),
      eligible = .data$drafted | .data$udfa | .data$seasons >= 3L,
      position_group = position_group(.data$position)
    ) |>
    dplyr::filter(.data$drafted | .data$last_season < .env$last_roster_season) |>
    dplyr::select(
      "playerId", "team", "last_season", "first_season", "seasons", "position",
      "position_group", "draft_class", "drafted", "draft_round", "udfa", "eligible"
    )
}
```

- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -am "feat(teams): exit_cohort attribution"`

### Task 5: `build_team_draft()`

**Files:** Modify `R/teams.R`, `tests/testthat/test-teams.R`.

- [ ] **Step 1: Write the failing test**

```r
test_that("build_team_draft aggregates exits by team, final season, position", {
  cohort <- tibble::tibble(
    playerId = c("1", "2", "3"), team = "LSU", last_season = 2019L,
    position_group = c("Quarterback", "Quarterback", "Offensive line"),
    drafted = c(TRUE, FALSE, FALSE), draft_round = c(1L, NA, NA),
    udfa = c(FALSE, TRUE, FALSE), eligible = c(TRUE, TRUE, FALSE)
  )
  ts <- tibble::tibble(
    team = "LSU", season = 2019L, conference = "SEC", tier = 3L, tier_label = "Power"
  )
  td <- build_team_draft(cohort, ts)
  qb <- td[td$position_group == "Quarterback", ]
  expect_equal(
    c(qb$n_exits, qb$n_eligible, qb$n_drafted, qb$n_round1, qb$n_udfa),
    c(2L, 2L, 1L, 1L, 1L)
  )
  expect_equal(qb$conference, "SEC")
  expect_equal(nrow(td), 2L)
  expect_equal(sum(td$n_exits), nrow(cohort))
})
```

- [ ] **Step 2:** Run tests. Expected: FAIL, function not found.

- [ ] **Step 3: Implement**

```r
#' Draft output per team, final college season, and position group
#'
#' Aggregates [exit_cohort()] to the team whose roster the player left, in
#' the season they left it, with that season's conference and tier from
#' [build_team_season()]. Rates are `n_drafted / n_eligible`.
#'
#' @param cohort Output of [exit_cohort()].
#' @param team_season Output of [build_team_season()].
#' @return One row per `(team, season, position_group)`.
#' @export
build_team_draft <- function(cohort, team_season) {
  cohort |>
    dplyr::group_by(.data$team, season = .data$last_season, .data$position_group) |>
    dplyr::summarise(
      n_exits = dplyr::n(),
      n_eligible = sum(.data$eligible),
      n_drafted = sum(.data$drafted),
      n_round1 = sum(.data$draft_round %in% 1L),
      n_udfa = sum(.data$udfa),
      .groups = "drop"
    ) |>
    dplyr::mutate(dplyr::across(dplyr::starts_with("n_"), as.integer)) |>
    dplyr::left_join(
      dplyr::select(team_season, "team", "season", "conference", "tier", "tier_label"),
      by = c("team", "season")
    ) |>
    dplyr::relocate("conference", "tier", "tier_label", .after = "season")
}
```

- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -am "feat(teams): build_team_draft"`

### Task 6: Contracts

**Files:** Modify `R/contracts.R` (append after `contract_career_summary`),
`tests/testthat/test-contracts.R`.

- [ ] **Step 1: Write the failing tests**

```r
test_that("contract_team_season passes a well-formed table and flags a bad record", {
  skip_if_not_installed("pointblank")
  ts <- tibble::tibble(
    team = c("LSU", "Montana"), season = 2019L, conference = c("SEC", "Big Sky"),
    classification = c("fbs", "fcs"), tier = c(3L, 1L),
    tier_label = c("Power", "FCS and below"),
    games_played = c(15L, 12L), wins = c(15L, 9L), losses = c(0L, 3L), ties = 0L,
    win_pct = c(1, 0.75), srs = c(34.2, NA), sp_overall = c(30.1, NA),
    n_roster = c(120L, 95L), n_stat_players = c(70L, 40L), has_stat_lines = TRUE
  )
  expect_true(pointblank::all_passed(contract_team_season(ts, stop_on_fail = FALSE)))
  bad <- ts
  bad$wins[1] <- 16L # wins + losses + ties != games_played
  expect_false(pointblank::all_passed(contract_team_season(bad, stop_on_fail = FALSE)))
  bad <- ts
  bad$tier[1] <- NA # an FBS team must carry a tier
  expect_false(pointblank::all_passed(contract_team_season(bad, stop_on_fail = FALSE)))
})

test_that("contract_team_draft checks counts and pick attribution coverage", {
  skip_if_not_installed("pointblank")
  cohort <- tibble::tibble(
    playerId = c("1", "2"), drafted = c(TRUE, FALSE), draft_class = 2020L
  )
  td <- tibble::tibble(
    team = "LSU", season = 2019L, conference = "SEC", tier = 3L,
    tier_label = "Power", position_group = "Quarterback",
    n_exits = 2L, n_eligible = 2L, n_drafted = 1L, n_round1 = 1L, n_udfa = 1L
  )
  picks <- tibble::tibble(playerId = "1", year = 2020L)
  expect_true(pointblank::all_passed(
    contract_team_draft(td, cohort, picks, reused = character(), min_class = 2014L,
                        stop_on_fail = FALSE)
  ))
  # A pick that never attributes drops coverage to 50% < 93%.
  picks2 <- tibble::tibble(playerId = c("1", "7"), year = 2020L)
  expect_false(pointblank::all_passed(
    contract_team_draft(td, cohort, picks2, reused = character(), min_class = 2014L,
                        stop_on_fail = FALSE)
  ))
  # Exit totals must equal the cohort (no silent loss in aggregation).
  td2 <- td
  td2$n_exits <- 3L
  td2$n_eligible <- 3L
  expect_false(pointblank::all_passed(
    contract_team_draft(td2, cohort, picks, reused = character(), min_class = 2014L,
                        stop_on_fail = FALSE)
  ))
})
```

- [ ] **Step 2:** Run `Rscript -e 'devtools::test(filter = "contracts")'`. Expected: FAIL, functions not found.

- [ ] **Step 3: Implement**

```r
#' Data contract for the team-season table
#'
#' Guards [build_team_season()]: one row per `(team, season)`, a record that
#' adds up, `win_pct` in [0, 1], non-negative counts, and a tier on every FBS
#' team-season (an untiered FBS conference means the tier lookup is stale).
#'
#' @param team_season Output of [build_team_season()].
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_team_season <- function(team_season, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(team_season, label = "team_season") |>
    pointblank::col_exists(c(
      "team", "season", "conference", "tier", "games_played", "wins",
      "losses", "ties", "win_pct", "n_roster", "n_stat_players"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(team, season)) |>
    pointblank::rows_distinct(pointblank::vars(team, season)) |>
    pointblank::col_vals_expr(rlang::expr(
      wins + losses + ties == games_played
    )) |>
    pointblank::col_vals_between("win_pct", 0, 1, na_pass = TRUE) |>
    pointblank::col_vals_gte(
      pointblank::vars(games_played, n_roster, n_stat_players), 0L
    ) |>
    pointblank::col_vals_not_null(
      pointblank::vars(tier),
      preconditions = function(x) dplyr::filter(x, .data$classification %in% "fbs")
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "team_season", stop_on_fail)
}

#' Data contract for the team draft table
#'
#' Guards [build_team_draft()]: one row per `(team, season, position_group)`;
#' drafted + UDFA <= eligible <= exits; exit totals equal the cohort (no
#' silent loss in aggregation); and at least `min_coverage` of id-bearing,
#' non-reused picks from `min_class` on are attributed to a team (picks with
#' no roster season before the draft cannot be credited).
#'
#' @param team_draft Output of [build_team_draft()].
#' @param cohort Output of [exit_cohort()].
#' @param picks Cleaned picks.
#' @param reused Reused athlete ids ([reused_ids()]).
#' @param min_class First draft class in the coverage check.
#' @param min_coverage Minimum attributed share (default 0.93; 94.6% observed
#'   2026-10-31).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_team_draft <- function(
  team_draft,
  cohort,
  picks,
  reused,
  min_class = 2014L,
  min_coverage = 0.93,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  n_picks <- picks |>
    dplyr::filter(
      !is.na(.data$playerId),
      !.data$playerId %in% reused,
      .data$year >= min_class
    ) |>
    dplyr::distinct(.data$playerId) |>
    nrow()
  n_attributed <- sum(cohort$drafted & cohort$draft_class >= min_class)
  coverage <- if (n_picks > 0) n_attributed / n_picks else 1
  n_cohort <- nrow(cohort)
  agent <- pointblank::create_agent(team_draft, label = "team_draft") |>
    pointblank::rows_distinct(pointblank::vars(team, season, position_group)) |>
    pointblank::col_vals_in_set(
      "position_group",
      c(position_group_levels(), "Position not recorded")
    ) |>
    pointblank::col_vals_expr(rlang::expr(n_drafted + n_udfa <= n_eligible)) |>
    pointblank::col_vals_expr(rlang::expr(n_eligible <= n_exits)) |>
    pointblank::col_vals_expr(rlang::expr(n_round1 <= n_drafted)) |>
    pointblank::col_vals_equal(
      "total_exits",
      n_cohort,
      preconditions = function(x) {
        dplyr::mutate(x, total_exits = sum(.data$n_exits))
      }
    ) |>
    pointblank::col_vals_gte(
      "coverage",
      min_coverage,
      preconditions = function(x) dplyr::mutate(x, coverage = .env$coverage)
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "team_draft", stop_on_fail)
}
```

- [ ] **Step 4:** Run tests. Expected: PASS. If `col_vals_gte` on a constant column misbehaves, compute `coverage` inside `preconditions` as written; do not move the check outside pointblank (the gate reads the agent).
- [ ] **Step 5:** Commit: `git commit -am "feat(contracts): team_season and team_draft contracts"`

### Task 7: Wire into `_targets.R`

**Files:** Modify `_targets.R`.

- [ ] **Step 1:** In the features block, after `player_season_stats` (line ~487), add:

```r
  # Team- and conference-grain derived tables (plans/conferences-teams.md,
  # decision 0033): credit each player's exit to their final pre-draft
  # roster team; derived like career/roster_flags, not published parquet.
  tar_target(
    team_season,
    build_team_season(roster, games, tiers, player_season, coaches)
  ),
  tar_target(
    exits,
    exit_cohort(
      roster,
      picks,
      udfa_ids = unique(outcomes$playerId[outcomes$outcome_signed_udfa_d %in% TRUE]),
      reused = reused
    )
  ),
  tar_target(team_draft, build_team_draft(exits, team_season)),
```

- [ ] **Step 2:** In the contracts block, after `ok_outcomes`, add:

```r
  tar_target(
    ok_team_season,
    pointblank::all_passed(
      contract_team_season(team_season, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_team_draft,
    pointblank::all_passed(
      contract_team_draft(team_draft, exits, picks, reused, stop_on_fail = FALSE)
    )
  ),
```

and add `team_season = ok_team_season, team_draft = ok_team_draft` to the `assert_contracts_pass(list(...))` in `contract_gate`.

- [ ] **Step 3:** Add `team_season = team_season, team_draft = team_draft,` to the `build_duckdb(list(...))` table list (before `audit_log`).

- [ ] **Step 4:** Add two audit steps inside `audit_log`'s `bind_rows()` (after `build_outcomes`):

```r
      audit_step(
        team_season,
        "build_team_season",
        "features",
        roster,
        keys = c("team", "season"),
        contract_passed = ok_team_season
      ),
      audit_step(
        team_draft,
        "build_team_draft",
        "features",
        exits,
        keys = c("team", "season", "position_group"),
        contract_passed = ok_team_draft
      )
```

- [ ] **Step 5:** Run `Rscript -e 'targets::tar_make()'`. Expected: completes; `contract_gate` passes.
- [ ] **Step 6:** Sanity-check against the planning facts:

```bash
Rscript -e '
library(targets); library(dplyr)
ts <- tar_read(team_season); td <- tar_read(team_draft); ex <- tar_read(exits)
print(ts |> filter(tier_label != "FCS and below") |> count(season, tier_label) |> tidyr::pivot_wider(names_from = tier_label, values_from = n))
cat("attributed 2014+ picks:", sum(ex$drafted & ex$draft_class >= 2014), "(expect ~3129)\n")
cat("FBS team-seasons with NA tier:", sum(ts$classification %in% "fbs" & is.na(ts$tier)), "(expect 0)\n")
print(td |> filter(season >= 2013) |> group_by(position_group) |> summarise(rate = sum(n_drafted) / sum(n_eligible)))
'
```

Expected: FBS counts per season match the profiling table in the spec (Power ~64–67, G5 ~55–71); 3,129 ± a few attributed; OL rate is non-zero and similar in size to other groups.
- [ ] **Step 7:** Commit: `git commit -am "feat(pipeline): team_season, exits, team_draft targets"`

### Task 8: Dictionaries, dict tests, data model

**Files:** Create `inst/dict/team_season.yml`, `inst/dict/team_draft.yml`;
modify `tests/testthat/test-dict-derived.R`, `inst/data-model.md`.

- [ ] **Step 1: Write the failing dict tests** (append to `test-dict-derived.R`)

```r
test_that("team_season dict matches build_team_season() output schema", {
  skip_if_not_installed("yaml")
  f <- team_fixture_dict()
  check_dict(
    "team_season",
    build_team_season(f$roster, f$games, f$tiers, f$player_season, f$coaches)
  )
})

test_that("team_draft dict matches build_team_draft() output schema", {
  skip_if_not_installed("yaml")
  f <- team_fixture_dict()
  ts <- build_team_season(f$roster, f$games, f$tiers, f$player_season, f$coaches)
  cohort <- exit_cohort(
    f$roster,
    tibble::tibble(playerId = "1", year = 2020L, round = 1L),
    udfa_ids = character(), reused = character(), last_roster_season = 2020L
  )
  check_dict("team_draft", build_team_draft(cohort, ts))
})
```

with a fixture helper at the top of the same file (copy of the Task 3
fixture so the file stands alone):

```r
team_fixture_dict <- function() {
  list(
    games = tibble::tibble(
      season = 2019L, completed = TRUE,
      homeTeam = "LSU", homeConference = "SEC", homeClassification = "fbs",
      homePoints = 42L, awayTeam = "Alabama", awayConference = "SEC",
      awayClassification = "fbs", awayPoints = 25L
    ),
    roster = tibble::tibble(
      playerId = c("1", "2"), season = 2019L, team = "LSU", position = c("QB", "OT")
    ),
    tiers = tibble::tibble(season = 2019L, conference = "SEC", tier = 3L, tier_label = "Power"),
    player_season = tibble::tibble(playerId = "1", season = 2019L, team = "LSU"),
    coaches = tibble::tibble(school = "LSU", season = 2019L, srs = 34.2, sp_overall = 30.1)
  )
}
```

- [ ] **Step 2:** Run `Rscript -e 'devtools::install(quick = TRUE, upgrade = "never"); devtools::test(filter = "dict-derived")'` (the dict test reads the installed `inst/dict`). Expected: FAIL, yml not found.

- [ ] **Step 3: Write `inst/dict/team_season.yml`**

```yaml
dataset: team_season
source: derived in-pipeline (build_team_season(roster, games, tiers, player_season, coaches))
grain: one team in one season (every division)
key: team, season
description: >
  One row per team per season for every team that played a game in `games`
  or appears on a roster: conference and season-aware tier, win-loss record
  from completed games, FBS ratings (SRS, SP+) from the coaches table, roster
  size, and how many players carry a stat line. Conferences absent from the
  tier lookup fall back to tier 1 for non-FBS teams. The current season's
  record is partial. A DERIVED table (decision 0021): in the DuckDB bundle,
  not published as parquet. Contract: `contract_team_season()`.
columns:
  - {name: team, type: string, description: School name (joins teams/roster/games by name)., provenance: games / roster}
  - {name: season, type: int32, description: Season., provenance: games / roster}
  - {name: conference, type: string, description: "Conference that season (most frequent in games; NA if the team has no games).", provenance: games}
  - {name: classification, type: string, description: "Division: fbs, fcs, ii, iii (NA without games).", provenance: games}
  - {name: tier, type: int32, description: "3 Power, 2 Group of 5, 1 FCS and below (decision 0003); non-FBS teams outside the lookup get 1.", provenance: derived (conference_tiers)}
  - {name: tier_label, type: string, description: Tier label., provenance: derived}
  - {name: games_played, type: int32, description: Completed games with a score., provenance: derived (games)}
  - {name: wins, type: int32, description: Wins in completed games., provenance: derived (games)}
  - {name: losses, type: int32, description: Losses in completed games., provenance: derived (games)}
  - {name: ties, type: int32, description: Ties in completed games., provenance: derived (games)}
  - {name: win_pct, type: double, description: "(wins + ties / 2) / games_played; NA with no completed games.", provenance: derived}
  - {name: srs, type: double, description: Simple Rating System (FBS only)., provenance: coaches}
  - {name: sp_overall, type: double, description: SP+ overall rating (FBS only)., provenance: coaches}
  - {name: n_roster, type: int32, description: Distinct players on the roster that season (0 if no roster)., provenance: derived (roster)}
  - {name: n_stat_players, type: int32, description: Distinct players with a stat line that season., provenance: derived (player_season)}
  - {name: has_stat_lines, type: logical, description: n_stat_players > 0., provenance: derived}
```

- [ ] **Step 4: Write `inst/dict/team_draft.yml`**

```yaml
dataset: team_draft
source: derived in-pipeline (build_team_draft(exit_cohort(...), team_season))
grain: one team x final college season x position group
key: team, season, position_group
description: >
  Players whose college career ended at a team, counted in the season they
  left (decision 0033). A drafted player is credited to their final roster
  season before the draft (earliest pick, decision 0011); an undrafted player
  to their final roster season. Undrafted players still on the latest roster
  are excluded (outcome unknown); reused ids excluded (decision 0022).
  Position group from the final-season roster position (`position_group()`).
  Eligible is a roster proxy: 3+ roster seasons, or drafted, or UDFA. UDFAs
  are only linked for players with a stat line, so offensive-line UDFAs are
  undercounted. A DERIVED table: DuckDB bundle only. Contract:
  `contract_team_draft()`.
columns:
  - {name: team, type: string, description: Team the player left., provenance: roster}
  - {name: season, type: int32, description: The player's final college season at the team., provenance: roster}
  - {name: conference, type: string, description: Team's conference that season., provenance: team_season}
  - {name: tier, type: int32, description: Team's tier that season., provenance: team_season}
  - {name: tier_label, type: string, description: Tier label., provenance: team_season}
  - {name: position_group, type: string, description: Reader-facing position group., provenance: derived (position_group())}
  - {name: n_exits, type: int32, description: Players whose college career ended here that season., provenance: derived}
  - {name: n_eligible, type: int32, description: Exits meeting the eligibility proxy., provenance: derived}
  - {name: n_drafted, type: int32, description: Exits drafted into the NFL., provenance: derived (picks)}
  - {name: n_round1, type: int32, description: Exits drafted in round 1., provenance: derived (picks)}
  - {name: n_udfa, type: int32, description: Undrafted exits who signed with an NFL team., provenance: derived (outcomes)}
```

- [ ] **Step 5:** Re-install and re-run the dict tests. Expected: PASS. Also run `devtools::test(filter = "duckdb")` in case it enumerates bundled tables.
- [ ] **Step 6:** In `inst/data-model.md`, add two rows to the table list next to `career_summary`:

```markdown
| `team_season` | one team in one season (every division) | [`dict/team_season.yml`](dict/team_season.yml) |
| `team_draft` | team × final college season × position group | [`dict/team_draft.yml`](dict/team_draft.yml) |
```

and in the mermaid ERD block add:

```
    roster |o--o{ team_season : "team, season (aggregated)"
    games |o--o{ team_season : "team, season (aggregated)"
    team_season ||--o{ team_draft : "team, season"
```

- [ ] **Step 7:** Commit: `git add inst/dict/team_*.yml && git commit -am "docs(dict): team_season and team_draft dictionaries"`

### Task 9: Decision record 0033

**Files:** Create `decisions/0033-team-draft-attribution.md` (copy the
`decisions/TEMPLATE.md` headings).

- [ ] **Step 1:** Fill it with: **Context** (conference/team series; the
  picks table's legacy conference names leave ~150 picks untiered; offensive
  linemen have almost no stat lines). **Decision** (credit to final pre-draft
  roster team and that season's conference; denominator = exits meeting the
  3-season/drafted/UDFA proxy; position group from final-season roster
  position via `position_group()`; win % from `games` for every division,
  SP+ as FBS check; non-FBS conferences outside the tier lookup → tier 1;
  rates use draft classes 2014+; FBS teams individually, FCS-and-below in
  aggregate). **Alternatives** (picks.collegeConference: legacy names;
  stat-line denominator: drops OL; raw counts: no rate; any-season credit:
  multi-team double counting, see the coaches post). **Consequences**
  (94.6% of 2014+ id-bearing picks attributed; OL UDFAs undercounted;
  players who transfer to a school outside roster coverage look like exits).
- [ ] **Step 2:** Commit: `git add decisions/0033-team-draft-attribution.md && git commit -m "docs(decisions): 0033 team draft attribution"`

---

## Post 1

Style rules: AGENTS.md "Blog style" and "Vignette writing critiques". Post 1
is **descriptive**: no expectation lines, no verdict emojis, and the Summary
table is a findings ledger (Finding / Evidence). Every number in prose,
captions, or annotations comes from a chunk and is pinned by `stopifnot()`.
Headings below are draft assertions; **reword each to match what the numbers
show** before committing (e.g. if top-10 share is 18%, say "about one in five").

### Task 10: Post 1 scaffold, load, and Data section

**Files:** Create `vignettes/2026-10-31-conferences-landscape.qmd`.

- [ ] **Step 1:** Copy `vignettes/_post-template.qmd` to the new file. Set the YAML:

```yaml
title: "College football's draft picks come from a few hundred FBS schools, and the data sees every FBS team but only part of the rest"
date: "2026-10-31"
description: "REWRITE after Task 12 with the measured numbers: tiers and team counts, stat-line coverage, the offensive-line blind spot, and top-school concentration."
followups:
  - "Which conferences and schools produce draftees above expectation, by position? (Post 2)"
  - "Do teams that win more produce more draftees? (Post 3)"
  - "Recover offensive-line careers from rosters alone so the model population can include them."
  - "Fill FCS-and-below rosters (2020 especially) from another source."
author:
  - "AI directed by Nick Giangreco"
freeze: auto
```

and the matching `%\VignetteIndexEntry{...}` (same string as `title:`). Keep
the template's `setup` chunk verbatim; delete the `registry` chunk unless a
named player is used (Task 12 adds one).

- [ ] **Step 2:** Replace the `load` chunk with:

```r
#| label: load
#| include: false
team_season <- dbReadTable(con, "team_season")
team_draft <- dbReadTable(con, "team_draft")
teams <- dbReadTable(con, "teams")
roster <- dbReadTable(con, "roster")
player_stats_seasons <- dbGetQuery(
  con,
  "SELECT DISTINCT playerId, season FROM player_stats"
)
stopifnot(nrow(team_season) > 0, nrow(team_draft) > 0)

tier_order <- c("Power", "Group of 5", "FCS and below")
tier_colors <- c(
  "Power" = "#1d4ed8", "Group of 5" = "#f59e0b", "FCS and below" = "#6b7280"
)
team_season <- team_season |>
  mutate(tier_label = factor(tier_label, levels = tier_order))
first_class <- 2014L # full observable careers (roster starts 2010)
```

- [ ] **Step 3:** Write the Introduction (one or two sentences, no expectations):

```markdown
## 1. Introduction

Every Saturday more than six hundred college programs play football, from
Alabama and Ohio State down to Division III, and this post maps who they
are, how they are grouped, what the data records about each, and how
unevenly the NFL draft draws from them. The answers set up two later posts:
which schools produce draftees at each position, and whether winning
explains it.
```

(Replace "six hundred" with the measured count of teams that played in the
latest complete season: `n_distinct(team_season$team[team_season$season == 2025 & team_season$games_played > 0])`.)

- [ ] **Step 4:** Write section 2.1 with a terms table:

````markdown
## 2. Data

### 2.1 Teams are grouped into conferences, and conferences into three tiers

Every term the post uses is defined below.

```{r}
#| label: terms
tibble::tribble(
  ~Term, ~Meaning,
  "Conference", "A league of schools that schedule each other and share a championship, such as the SEC or the Big Sky.",
  "Tier", "Our three-level grouping of conferences by competitive level, set season by season because schools change conferences.",
  "Power", "The top tier: the SEC, Big Ten, ACC, Big 12, and (until 2024) the Pac-12, plus Notre Dame.",
  "Group of 5", "The rest of the top division (FBS): the American, Mountain West, Sun Belt, MAC, Conference USA, and others.",
  "FCS and below", "Every lower division: the FCS (such as the Big Sky or MVFC), Division II, and Division III.",
  "Team-season", "One school in one season.",
  "Stat line", "At least one recorded statistic (a carry, catch, tackle, kick) for a player in a season.",
  "Draft pick", "A player selected in the NFL draft, credited to the last college roster the player was on before the draft.",
  "UDFA", "Undrafted free agent: a player not drafted who signed with an NFL team anyway."
) |>
  kable(caption = "Terms used throughout.")
```
````

Check the Power/G5 conference lists against
`team_season |> filter(tier_label != "FCS and below") |> distinct(season, conference, tier_label)`
and correct names to the data's spelling before committing.

- [ ] **Step 5:** Render just this post to check it knits:
  `quarto render vignettes/2026-10-31-conferences-landscape.qmd` (set
  `CFB2NFL_ROOT=$(pwd)` in the environment). Expected: HTML with Introduction and 2.1.
- [ ] **Step 6:** Commit: `git add vignettes/2026-10-31-conferences-landscape.qmd && git commit -m "feat(blog): conferences landscape post scaffold"`

### Task 11: Post 1 sections 3.1 and 3.2

**Files:** Modify `vignettes/2026-10-31-conferences-landscape.qmd`.

- [ ] **Step 1: Section 3.1, conferences and realignment.** Heading (reword to the numbers):
  `### 3.1 About 130 FBS teams sit in ten conferences, and realignment moved dozens of them`. One or two sentences, then:

```r
#| label: s31-table
conf_counts <- team_season |>
  filter(games_played > 0, season %in% c(2010L, 2014L, 2020L, 2024L, 2025L)) |>
  group_by(Season = season, Tier = tier_label) |>
  summarise(Conferences = n_distinct(conference), Teams = n_distinct(team), .groups = "drop")
kable(conf_counts, caption = "Conferences and teams that played, by tier, in selected seasons.")
```

```r
#| label: s31-explain
#| fig-height: 6
fbs_n <- team_season |>
  filter(classification == "fbs", games_played > 0, season < 2026L) |>
  count(season, tier_label)
p <- ggplot(fbs_n, aes(season, n, color = tier_label)) +
  geom_line(linewidth = 1.4) +
  geom_point_interactive(
    aes(tooltip = paste0(season, ": ", n, " ", tier_label, " teams"), data_id = paste(season, tier_label)),
    size = 3
  ) +
  annotate("text", x = 2024, y = max(fbs_n$n) + 4, label = "2024: Pac-12 breaks up", hjust = 1, fontface = "bold") +
  annotate("curve", x = 2023.8, xend = 2024, y = max(fbs_n$n) + 3, yend = fbs_n$n[fbs_n$season == 2024 & fbs_n$tier_label == "Power"] + 1, curvature = -0.2, arrow = grid::arrow(length = grid::unit(0.2, "cm"))) +
  scale_color_manual(values = tier_colors, name = NULL) +
  labs(x = "Season", y = "Teams", title = "FBS teams by tier, each season") +
  theme_cfb2nfl()
girafe(ggobj = p, width_svg = 13, height_svg = 6)
```

```r
#| label: s31-explore
#| fig-height: 10
movers <- team_season |>
  filter(classification == "fbs", games_played > 0) |>
  group_by(team) |>
  filter(n_distinct(conference) > 1) |>
  ungroup()
p <- ggplot(movers, aes(season, reorder(team, season, min), fill = tier_label)) +
  geom_tile_interactive(
    aes(tooltip = paste0(team, ", ", season, ": ", conference, " (", tier_label, ")"), data_id = team),
    color = "white"
  ) +
  scale_fill_manual(values = tier_colors, name = NULL) +
  labs(x = "Season", y = NULL, title = "Every FBS team that changed conference, season by season") +
  theme_cfb2nfl(base_size = 12)
girafe(ggobj = p, width_svg = 13, height_svg = 10)
```

```r
#| label: s31-pin
#| include: false
stopifnot(
  n_distinct(movers$team) > 20,
  "SEC" %in% movers$conference[movers$team == "Texas"]
)
```

Name Texas and Oklahoma (to the SEC, 2024) and the Pac-12 schools in the
sentence only if the pins above hold; add a pin for each additional named fact.

- [ ] **Step 2: Section 3.2, stat-line coverage.** Heading (reword):
  `### 3.2 Every FBS team has stat lines, but FCS and below is patchy and nearly vanishes in 2020`. Then:

```r
#| label: s32-table
coverage <- team_season |>
  filter(games_played > 0) |>
  group_by(Season = season, Tier = tier_label) |>
  summarise(
    `Teams that played` = n(),
    `With stat lines` = sum(has_stat_lines),
    `Median players with a stat line` = median(n_stat_players[has_stat_lines]),
    .groups = "drop"
  )
kable(coverage, caption = "Teams that played, teams with at least one player stat line, and stat depth, by season and tier.")
```

```r
#| label: s32-explain
#| fig-height: 6
cov_share <- coverage |>
  mutate(share = `With stat lines` / `Teams that played`)
p <- ggplot(cov_share, aes(Season, share, color = Tier)) +
  geom_line(linewidth = 1.4) +
  geom_point_interactive(
    aes(tooltip = paste0(Season, ", ", Tier, ": ", `With stat lines`, " of ", `Teams that played`, " teams"), data_id = paste(Season, Tier)),
    size = 3
  ) +
  annotate("text", x = 2020, y = 0.05, label = "2020: COVID spring season", hjust = -0.05, fontface = "bold") +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  scale_color_manual(values = tier_colors, name = NULL) +
  labs(x = "Season", y = "Teams with stat lines", title = "Share of teams with any player stat line") +
  theme_cfb2nfl()
girafe(ggobj = p, width_svg = 13, height_svg = 6)
```

```r
#| label: s32-explore
#| fig-height: 6
p <- ggplot(coverage, aes(Season, `Median players with a stat line`, color = Tier)) +
  geom_line(linewidth = 1.2) +
  geom_point_interactive(
    aes(tooltip = paste0(Season, ", ", Tier, ": median ", `Median players with a stat line`, " players per team"), data_id = paste(Season, Tier)),
    size = 3
  ) +
  geom_vline(xintercept = 2015.5, linetype = "dashed") +
  annotate("text", x = 2015.6, y = 5, label = "2016: deeper stat records begin", hjust = 0, fontface = "bold") +
  scale_color_manual(values = tier_colors, name = NULL) +
  labs(x = "Season", y = "Median players with a stat line", title = "Players with a stat line per team") +
  theme_cfb2nfl()
girafe(ggobj = p, width_svg = 13, height_svg = 6)
```

```r
#| label: s32-pin
#| include: false
fbs_cov <- cov_share |> filter(Tier != "FCS and below", Season < 2026L)
stopifnot(
  all(fbs_cov$share >= 0.95),
  cov_share$`With stat lines`[cov_share$Season == 2020L & cov_share$Tier == "FCS and below"] < 30
)
```

- [ ] **Step 3:** Render the post; fix any error. Expected: both sections render, pins hold.
- [ ] **Step 4:** Commit: `git commit -am "feat(blog): landscape sections on tiers and coverage"`

### Task 12: Post 1 sections 3.3, 3.4, 3.5

**Files:** Modify `vignettes/2026-10-31-conferences-landscape.qmd`.

- [ ] **Step 1: Section 3.3, the offensive-line blind spot** (single fact: table + one figure). Heading (reword):
  `### 3.3 Offensive linemen fill rosters but almost never have a stat line`.

```r
#| label: s33-table
ol_cov <- roster |>
  filter(season < 2026L) |>
  distinct(playerId, season, position) |>
  left_join(mutate(player_stats_seasons, has_stat = TRUE), by = c("playerId", "season")) |>
  mutate(group = position_group(position), has_stat = coalesce(has_stat, FALSE)) |>
  group_by(`Position group` = group) |>
  summarise(
    `Roster player-seasons` = n(),
    `With a stat line` = sum(has_stat),
    Share = mean(has_stat),
    .groups = "drop"
  ) |>
  arrange(Share)
kable(
  mutate(ol_cov, Share = pct(Share)),
  caption = "Roster player-seasons and how many carry a stat line, by position group, 2010 to 2025."
)
```

```r
#| label: s33-explain
#| fig-height: 6
p <- ggplot(ol_cov, aes(Share, reorder(`Position group`, Share), fill = `Position group` == "Offensive line")) +
  geom_col_interactive(aes(
    tooltip = paste0(`Position group`, ": ", fmt(`With a stat line`), " of ", fmt(`Roster player-seasons`), " (", pct(Share), ")"),
    data_id = `Position group`
  )) +
  scale_fill_manual(values = c(`TRUE` = "#b91c1c", `FALSE` = "#9ca3af"), guide = "none") +
  scale_x_continuous(labels = scales::percent) +
  labs(x = "Roster player-seasons with a stat line", y = NULL, title = "Offensive linemen are on rosters but not in the stat sheets") +
  theme_cfb2nfl()
girafe(ggobj = p, width_svg = 13, height_svg = 6)
```

```r
#| label: s33-pin
#| include: false
stopifnot(ol_cov$`Position group`[1] == "Offensive line", ol_cov$Share[1] < 0.15)
```

The sentence says why this matters for the series: draftee rates in Posts 2
and 3 divide by everyone who left a roster, so linemen are counted.

- [ ] **Step 2: Section 3.4, concentration.** Heading (reword):
  `### 3.4 A few dozen schools supply most draft picks`.

```r
#| label: s34-table
school_picks <- team_draft |>
  filter(season >= first_class - 1L, season < 2026L) |>
  group_by(team) |>
  summarise(picks = sum(n_drafted), tier = first(tier_label), conference = last(conference), .groups = "drop") |>
  filter(picks > 0) |>
  arrange(desc(picks)) |>
  mutate(rank = row_number(), cum_share = cumsum(picks) / sum(picks))
conc <- tibble::tibble(
  Schools = c("Top 10", "Top 25", "Top 50", "All schools with a pick"),
  n = c(10L, 25L, 50L, nrow(school_picks))
) |>
  mutate(`Share of picks` = pct(school_picks$cum_share[n]))
kable(select(conc, -n), caption = "Share of draft picks (2014 and later classes) from the top schools.")
```

```r
#| label: s34-explain
#| fig-height: 6
p <- ggplot(school_picks, aes(rank, cum_share)) +
  geom_step(linewidth = 1.3) +
  geom_point_interactive(
    data = filter(school_picks, rank <= 10),
    aes(tooltip = paste0("#", rank, " ", team, ": ", picks, " picks"), data_id = team),
    color = "#b91c1c", size = 3
  ) +
  geom_hline(yintercept = 0.5, linetype = "dashed") +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  labs(x = "Schools, ranked by draft picks", y = "Cumulative share of picks", title = "How many schools it takes to account for the draft") +
  theme_cfb2nfl()
girafe(ggobj = p, width_svg = 13, height_svg = 6)
```

```r
#| label: s34-explore
#| fig-height: 12
top <- filter(school_picks, rank <= 60)
p <- ggplot(top, aes(picks, reorder(team, picks), fill = team)) +
  geom_col_interactive(aes(
    tooltip = paste0(team, " (", conference, ", ", tier, "): ", picks, " picks"),
    data_id = team
  )) +
  scale_fill_team(teams, guide = "none") +
  labs(x = "Draft picks, 2014 and later classes", y = NULL, title = "The 60 schools with the most draft picks") +
  theme_cfb2nfl(base_size = 12)
girafe(ggobj = p, width_svg = 13, height_svg = 12)
```

```r
#| label: s34-pin
#| include: false
stopifnot(nrow(school_picks) > 200, school_picks$cum_share[25] > 0.4)
```

- [ ] **Step 3: Section 3.5, small schools.** Heading (reword):
  `### 3.5 Small schools still send players to the draft, North Dakota State most of all`. First verify the cast:

```bash
Rscript -e 'p <- targets::tar_read(picks); print(p[p$collegeTeam == "North Dakota State", c("name","year","round","overall","playerId")])'
```

Add the verified Carson Wentz (2016) and Trey Lance (2021) ids to the
`registry` chunk if their `playerId` is present; otherwise name only facts
pinnable from `picks`.

```r
#| label: s35-table
small <- team_draft |>
  filter(season >= first_class - 1L, season < 2026L, tier_label == "FCS and below") |>
  group_by(Season = season + 1L) |>
  summarise(`Draft picks` = sum(n_drafted), `Schools with a pick` = n_distinct(team[n_drafted > 0]), .groups = "drop")
kable(small, caption = "Draft picks from FCS-and-below schools, by draft class (the class after the player's final college season).")
```

```r
#| label: s35-explain
#| fig-height: 7
small_schools <- school_picks |> filter(tier == "FCS and below") |> slice_max(picks, n = 15, with_ties = FALSE)
p <- ggplot(small_schools, aes(picks, reorder(team, picks), fill = rank == min(rank))) +
  geom_col_interactive(aes(tooltip = paste0(team, " (", conference, "): ", picks, " picks"), data_id = team)) +
  scale_fill_manual(values = c(`TRUE` = "#15803d", `FALSE` = "#9ca3af"), guide = "none") +
  labs(x = "Draft picks, 2014 and later classes", y = NULL, title = "FCS-and-below schools with the most draft picks") +
  theme_cfb2nfl()
girafe(ggobj = p, width_svg = 13, height_svg = 7)
```

```r
#| label: s35-pin
#| include: false
picks_tbl <- dbReadTable(con, "picks")
stopifnot(
  small_schools$team[1] == "North Dakota State",
  any(picks_tbl$name == "Carson Wentz" & picks_tbl$collegeTeam == "North Dakota State" & picks_tbl$year == 2016L)
)
```

Note on the season-to-class shift in `s35-table`: drafted players credited
two or three seasons before the draft (24 cases) shift by one row; say so in
the caption if any FCS case is among them.

- [ ] **Step 4:** Render; fix errors; adjust headings to the numbers.
- [ ] **Step 5:** Commit: `git commit -am "feat(blog): landscape sections on linemen, concentration, small schools"`

### Task 13: Post 1 Summary, Discussion, final read

- [ ] **Step 1: Summary** (one sentence + findings ledger):

```r
#| label: summary
tibble::tribble(
  ~Finding, ~Evidence,
  "FBS has about 130 teams across the top two tiers", "Section 3.1 table",
  "Stat lines cover every FBS team, part of FCS and below", "Section 3.2 coverage share",
  "Offensive linemen almost never have stat lines", "Section 3.3 share",
  "A few dozen schools supply most picks", "Section 3.4 top-25 share",
  "Small schools still produce picks", "Section 3.5 counts"
) |>
  kable(caption = "What the landscape shows.")
```

Replace each Evidence cell with the inline pinned number (`r pct(...)`).

- [ ] **Step 2: Discussion:** one or two `callout-important` blocks (e.g.
  "Draft output is concentrated, so a per-player rate is needed before
  calling a school a producer: Post 2." and "Stat-based models miss
  offensive linemen; the roster sees them."), then a caveats paragraph:
  FCS-and-below rosters incomplete; 2020 spring season; 2026 partial;
  credit goes to the final college team (transfers credit the last stop);
  94.6% of 2014+ picks with an athlete id are attributable.
- [ ] **Step 3:** Rewrite `description:` with the measured numbers (one
  declarative sentence). Re-check title is one declarative sentence with no
  colon and matches `VignetteIndexEntry`. Search the file for em dashes:
  `grep -n "—" vignettes/2026-10-31-conferences-landscape.qmd` → expect none.
- [ ] **Step 4:** Render the full site locally per AGENTS.md
  (`CFB2NFL_ROOT=$(pwd) Rscript -e 'altdoc::render_docs()'`) and confirm the
  post appears in the Blog index table. Commit `_freeze/` output for the post.
- [ ] **Step 5:** Commit: `git add vignettes/ && git commit -m "feat(blog): conferences landscape summary and discussion"`

### Task 14: Ship

- [ ] **Step 1:** `air format .` then `Rscript -e 'devtools::document(); devtools::test()'`. Expected: 0 failures.
- [ ] **Step 2:** `Rscript -e 'devtools::check()'`. Expected: 0 errors / 0 warnings / 0 notes (exported functions need roxygen; `@export` added in Tasks 1–6; `utils::globalVariables` in `R/globals.R` if check flags pointblank `vars()` names like `team`, `season`, `position_group`).
- [ ] **Step 3:** Add a `NEWS.md` entry at the top of the dev section:

```markdown
- New derived tables `team_season` and `team_draft` in the DuckDB bundle
  ([decision 0033](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0033-team-draft-attribution.md)):
  every team's season record, tier, roster size and stat coverage, and draft
  picks and undrafted signings credited to the player's final college team,
  by position group (offensive linemen included).
- New blog post on the college football landscape
  ([vignettes/2026-10-31-conferences-landscape.qmd](https://github.com/ngiangre/cfb2nfl/blob/main/vignettes/2026-10-31-conferences-landscape.qmd)).
```

- [ ] **Step 4:** Commit, push the branch, open a PR via the `gh` R package
  (not the CLI):

```r
gh::gh("POST /repos/{owner}/{repo}/pulls", owner = "ngiangre", repo = "cfb2nfl",
  head = "feat/conferences-teams", base = "main",
  title = "feat: team tables and conferences landscape post",
  body = "Adds team_season/team_draft (decision 0033) and Post 1 of the conferences series.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)")
```

- [ ] **Step 5:** Wait for CI (check, format-check, site). Merge only after it
  passes and the user approves: `gh::gh("PUT /repos/{owner}/{repo}/pulls/{n}/merge", ..., merge_method = "squash")`.
- [ ] **Step 6:** Mark Post 1 done in `plans/conferences-teams.md`; write
  the Post 2 implementation plan next (it reuses `team_draft`).
