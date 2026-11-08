# Season calendar and the CFB2NFL_REFRESH_SEASONS selector (decision 0034).
# Pure date and string logic: no API calls, no network.

test_that("current_season flips on August 1, not earlier or later", {
  expect_identical(current_season(as.Date("2026-01-15")), 2025L)
  expect_identical(current_season(as.Date("2026-07-31")), 2025L)
  expect_identical(current_season(as.Date("2026-08-01")), 2026L)
  expect_identical(current_season(as.Date("2026-12-31")), 2026L)
})

test_that("January bowls belong to the prior season", {
  # The national championship is played in mid-January.
  expect_identical(current_season(as.Date("2027-01-11")), 2026L)
})

test_that("draft_season flips on May 1, the day after the late-April draft", {
  expect_identical(draft_season(as.Date("2026-01-15")), 2025L)
  expect_identical(draft_season(as.Date("2026-04-30")), 2025L)
  expect_identical(draft_season(as.Date("2026-05-01")), 2026L)
  expect_identical(draft_season(as.Date("2026-12-31")), 2026L)
})

test_that("draft_season differs from current_season only from May to July", {
  for (d in c("2026-05-01", "2026-06-15", "2026-07-31")) {
    expect_identical(draft_season(as.Date(d)), 2026L)
    expect_identical(current_season(as.Date(d)), 2025L)
  }
  for (d in c("2026-08-01", "2026-11-05", "2027-01-15", "2027-04-30")) {
    expect_identical(draft_season(as.Date(d)), current_season(as.Date(d)))
  }
})

test_that("refresh_season_for maps each source group on its calendar", {
  jan <- as.Date("2026-01-15")
  # CFB season data is the season that ended in December.
  expect_identical(refresh_season_for("games", jan), 2025L)
  expect_identical(refresh_season_for("roster", jan), 2025L)
  # Recruiting is the class enrolled in the current CFB season.
  expect_identical(refresh_season_for("recruiting", jan), 2025L)
  # Draft-keyed sources: the draft has not happened yet in January.
  expect_identical(refresh_season_for("picks", jan), 2025L)
  expect_identical(refresh_season_for("nfl_draft_picks", jan), 2025L)
  # NFL seasons run September to February, keyed by starting year.
  expect_identical(refresh_season_for("nfl_player_stats", jan), 2025L)

  apr30 <- as.Date("2026-04-30")
  expect_identical(refresh_season_for("picks", apr30), 2025L)
  expect_identical(refresh_season_for("games", apr30), 2025L)

  may1 <- as.Date("2026-05-01")
  expect_identical(refresh_season_for("picks", may1), 2026L)
  expect_identical(refresh_season_for("combine", may1), 2026L)
  expect_identical(refresh_season_for("games", may1), 2025L)

  dec31 <- as.Date("2026-12-31")
  expect_identical(refresh_season_for("games", dec31), 2026L)
  expect_identical(refresh_season_for("recruiting", dec31), 2026L)
})

test_that("refresh_season_for rejects unknown or non-season sources", {
  expect_error(refresh_season_for("teams"), "Unknown season-keyed source")
  expect_error(refresh_season_for(c("games", "roster")), "single source name")
  expect_error(refresh_season_for(NA_character_), "single source name")
})

test_that("an unset or empty selector is the full window to the current season", {
  d <- as.Date("2026-11-05")
  expect_identical(refresh_seasons("", source = "games", date = d), 2010:2026)
  expect_identical(refresh_seasons(NA, source = "games", date = d), 2010:2026)
  expect_identical(refresh_seasons(NULL, source = "games", date = d), 2010:2026)
  # Recruiting's window runs to the enrolled class, not the incoming one.
  expect_identical(
    refresh_seasons("", source = "recruiting", date = d),
    2010:2026
  )
  # The env var is read when the spec is not given.
  withr::with_envvar(
    c(CFB2NFL_REFRESH_SEASONS = NA),
    expect_identical(refresh_seasons(source = "games", date = d), 2010:2026)
  )
})

test_that("the selector accepts current, a single year, a range and a list", {
  d <- as.Date("2026-11-05")
  expect_identical(
    refresh_seasons("current", source = "games", date = d),
    2026L
  )
  expect_identical(
    refresh_seasons("current", source = "recruiting", date = d),
    2026L
  )
  expect_identical(refresh_seasons("2024", source = "games", date = d), 2024L)
  expect_identical(
    refresh_seasons("2010:2012", source = "games", date = d),
    2010:2012
  )
  expect_identical(
    refresh_seasons("2021,2023:2024", source = "games", date = d),
    c(2021L, 2023L, 2024L)
  )
  # Whitespace, duplicates and out-of-order tokens are normalised.
  expect_identical(
    refresh_seasons(" 2024 , 2022 ,2024", source = "games", date = d),
    c(2022L, 2024L)
  )
  expect_identical(
    refresh_seasons("current,2024", source = "games", date = d),
    c(2024L, 2026L)
  )
})

test_that("the selector follows the source's calendar, not a fixed window", {
  # On 2026-01-15 the CFB window ends at 2025, so 2026 is out of window.
  jan <- as.Date("2026-01-15")
  expect_identical(
    refresh_seasons("current", source = "games", date = jan),
    2025L
  )
  expect_warning(
    out <- refresh_seasons("2025,2026", source = "games", date = jan),
    "Dropping seasons"
  )
  expect_identical(out, 2025L)
})

test_that("seasons outside the window are dropped with a warning", {
  d <- as.Date("2026-11-05")
  expect_warning(
    out <- refresh_seasons("2025,2027", source = "games", date = d),
    "Dropping seasons outside"
  )
  expect_identical(out, 2025L)

  expect_warning(
    out <- refresh_seasons(
      "2005:2011",
      source = "games",
      min_season = 2010L,
      date = d
    ),
    "Dropping seasons outside"
  )
  expect_identical(out, 2010:2011)
})

test_that("a selector that clamps to nothing is an error", {
  d <- as.Date("2026-11-05")
  expect_error(
    suppressWarnings(refresh_seasons("2027", source = "games", date = d)),
    "selects no season"
  )
  expect_error(
    suppressWarnings(refresh_seasons("2000", source = "games", date = d)),
    "selects no season"
  )
})

test_that("invalid selector strings abort with a helpful message", {
  d <- as.Date("2026-11-05")
  expect_error(
    refresh_seasons("abc", source = "games", date = d),
    "Unrecognized token"
  )
  expect_error(
    refresh_seasons("2024-2025", source = "games", date = d),
    "Unrecognized token"
  )
  expect_error(
    refresh_seasons("20240", source = "games", date = d),
    "Unrecognized token"
  )
  expect_error(
    refresh_seasons("2024 2025", source = "games", date = d),
    "Unrecognized token"
  )
  expect_error(
    refresh_seasons("2025:2021", source = "games", date = d),
    "runs backwards"
  )
  expect_error(
    refresh_seasons("2021,,2023", source = "games", date = d),
    "Empty token"
  )
  expect_error(
    refresh_seasons("2021,", source = "games", date = d),
    "Empty token"
  )
  expect_error(
    refresh_seasons(c("2024", "2025"), source = "games", date = d),
    "single string"
  )
  expect_error(
    refresh_seasons(list(2024), source = "games", date = d),
    "single string"
  )
})

test_that("bad arguments to the selector are rejected", {
  d <- as.Date("2026-11-05")
  expect_error(
    refresh_seasons("", source = "teams", date = d),
    "Unknown season-keyed source"
  )
  expect_error(
    refresh_seasons(
      "",
      source = "games",
      min_season = c(2010L, 2011L),
      date = d
    ),
    "single year"
  )
  expect_error(
    refresh_seasons("", source = "games", min_season = 2030L, date = d),
    "empty"
  )
})

# ---- season splice (decision 0034) -------------------------------------------

splice_fixture <- function(dir) {
  path <- file.path(dir, "t.parquet")
  arrow::write_parquet(
    tibble::tibble(season = c(2024L, 2024L, 2025L, 2025L), x = c(1, 2, 3, 4)),
    path
  )
  path
}

test_that("splice_seasons replaces only the refreshed seasons", {
  path <- splice_fixture(withr::local_tempdir())
  fresh <- tibble::tibble(season = c(2025L, 2025L, 2025L), x = c(30, 40, 50))
  out <- splice_seasons(fresh, path, "season", 2025L)
  expect_equal(sort(out$x), c(1, 2, 30, 40, 50))
  expect_equal(sum(out$season == 2024L), 2L)
})

test_that("splice_seasons adds a new season and keeps column order", {
  path <- splice_fixture(withr::local_tempdir())
  fresh <- tibble::tibble(x = 9, season = 2026L)
  out <- splice_seasons(fresh, path, "season", 2026L)
  expect_equal(names(out), c("season", "x"))
  expect_equal(nrow(out), 5L)
})

test_that("splice_seasons returns the fresh table on a full refresh", {
  fresh <- tibble::tibble(season = 2010L, x = 1)
  expect_identical(
    splice_seasons(
      fresh,
      "does-not-exist.parquet",
      "season",
      2010L,
      full = TRUE
    ),
    fresh
  )
})

test_that("splice_seasons refuses to run without the published file", {
  expect_error(
    splice_seasons(
      tibble::tibble(season = 2025L),
      "nope.parquet",
      "season",
      2025L
    ),
    "data-latest"
  )
})

test_that("splice_seasons refuses a schema change", {
  path <- splice_fixture(withr::local_tempdir())
  fresh <- tibble::tibble(season = 2025L, x = 1, y = 2)
  expect_error(splice_seasons(fresh, path, "season", 2025L), "full refresh")
})

test_that("splice_seasons refuses a truncated pull", {
  path <- splice_fixture(withr::local_tempdir())
  fresh <- tibble::tibble(season = 2025L, x = 1)
  # 1 of 2 published rows is exactly the 50% floor: allowed.
  expect_equal(nrow(splice_seasons(fresh, path, "season", 2025L)), 3L)
  expect_error(
    splice_seasons(fresh, path, "season", 2025L, min_ratio = 0.75),
    "shrank"
  )
  # Refreshing a season that returns no rows at all is a truncation.
  expect_error(
    splice_seasons(
      tibble::tibble(season = integer(), x = double()),
      path,
      "season",
      2024L
    ),
    "shrank"
  )
})

test_that("splice_seasons re-dedupes recruiting to one row per athlete", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "r.parquet")
  old <- tibble::tibble(
    playerId = c("a", "b"),
    hs_class = c(2025L, 2026L),
    stars = c(3L, 3L),
    rating = c(0.85, 0.80)
  )
  arrow::write_parquet(old, path)
  # "a" reappears in the refreshed 2026 class with a higher rating.
  fresh <- tibble::tibble(
    playerId = c("a", "b"),
    hs_class = c(2026L, 2026L),
    stars = c(4L, 3L),
    rating = c(0.90, 0.81)
  )
  out <- splice_seasons(
    fresh,
    path,
    "hs_class",
    2026L,
    dedupe = dedupe_recruiting
  )
  expect_equal(nrow(out), 2L)
  expect_equal(out$rating[out$playerId == "a"], 0.90)
  expect_equal(out$rating[out$playerId == "b"], 0.81)
})

test_that("refresh_is_full distinguishes the full window from a slice", {
  d <- as.Date("2026-11-05")
  expect_true(refresh_is_full("", "roster", date = d))
  expect_true(refresh_is_full("2010:2026", "roster", date = d))
  expect_false(refresh_is_full("current", "roster", date = d))
  expect_true(refresh_is_full("2010:2026", "recruiting", date = d))
  expect_false(refresh_is_full("2011:2026", "recruiting", date = d))
})

test_that("estimate_refresh_calls counts calls per endpoint", {
  games <- tibble::tibble(
    season = c(2025L, 2025L, 2025L, 2026L, 2026L),
    seasonType = c("regular", "regular", "postseason", "regular", "regular"),
    week = c(1L, 2L, 1L, 1L, 2L),
    completed = c(TRUE, TRUE, TRUE, TRUE, FALSE)
  )
  seasons <- list(
    games = 2026L,
    player_stats = 2026L,
    roster = 2026L,
    recruiting = 2027L
  )
  est <- estimate_refresh_calls(seasons, games)
  expect_equal(est[["games"]], 2L)
  expect_equal(est[["game_team_stats"]], 1L)
  expect_equal(est[["plays"]], 1L)
  expect_equal(est[["play_stats"]], 0L)
  expect_equal(est[["total"]], 2L + 1L + 1L + 1L + 1L + 1L + 1L + 5L)
  # The opt-in per-game play-stats pull costs one call per game.
  est_ps <- estimate_refresh_calls(seasons, games, play_stats_games = 120L)
  expect_equal(est_ps[["total"]] - est[["total"]], 120L)
  # An unpublished season assumes the default week count.
  est_new <- estimate_refresh_calls(
    list(
      games = 2027L,
      player_stats = 2027L,
      roster = 2027L,
      recruiting = 2028L
    ),
    games,
    default_weeks = 15L
  )
  expect_equal(est_new[["game_player_stats"]], 15L)
})

test_that("contract_season_coverage flags a missing season", {
  ok <- contract_season_coverage(
    list(roster = c(2024L, 2025L, 2026L)),
    required = list(roster = 2024:2025),
    stop_on_fail = FALSE
  )
  expect_true(pointblank::all_passed(ok))
  gap <- contract_season_coverage(
    list(roster = c(2024L, 2026L)),
    required = list(roster = 2024:2025),
    stop_on_fail = FALSE
  )
  expect_false(pointblank::all_passed(gap))
})

test_that("required_seasons stops before each source's current season", {
  r <- required_seasons(c("roster", "recruiting"), date = as.Date("2026-11-05"))
  expect_equal(range(r$roster), c(2010L, 2025L))
  expect_equal(range(r$recruiting), c(2010L, 2025L))
})
