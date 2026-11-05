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
  # Recruiting is the incoming class, one ahead of the CFB season.
  expect_identical(refresh_season_for("recruiting", jan), 2026L)
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
  expect_identical(refresh_season_for("recruiting", dec31), 2027L)
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
  # Recruiting's window runs to the incoming class.
  expect_identical(
    refresh_seasons("", source = "recruiting", date = d),
    2010:2027
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
    2027L
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
