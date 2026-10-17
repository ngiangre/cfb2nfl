test_that("clean_picks coerces the athlete id to a string key and flags drafted", {
  raw <- tibble::tibble(
    collegeAthleteId = c(101L, NA_integer_),
    year = c(2015L, 2016L)
  )
  out <- clean_picks(raw)
  expect_type(out$playerId, "character")
  expect_equal(out$playerId, c("101", NA_character_))
  expect_true(all(out$drafted))
})

test_that("clean_coaches builds a tidy head-coach-season schema", {
  raw <- tibble::tibble(
    id = 7L,
    firstName = "Nick",
    lastName = "Saban",
    seasons_school = "Alabama",
    seasons_conference = "SEC",
    seasons_year = 2015L,
    seasons_games = 15L,
    seasons_wins = 14L,
    seasons_losses = 1L,
    seasons_srs = 20,
    seasons_spOverall = 30,
    seasons_spOffense = 25,
    seasons_spDefense = 5
  )
  out <- clean_coaches(raw)
  expect_equal(out$coach_name, "Nick Saban")
  expect_equal(out$school, "Alabama")
  expect_type(out$season, "integer")
  expect_true(all(c("srs", "sp_offense", "sp_defense") %in% names(out)))
})

test_that("clean_teams dedupes duplicate school names, keeping the real program", {
  # A duplicated school name: the real program (has classification + logo) plus
  # a phantom row (NA classification, no logo). Dedupe must keep the real one.
  raw <- tibble::tibble(
    id = c(3237L, 2653L),
    school = c("Troy", "Troy"),
    mascot = c(NA, "Trojans"),
    abbreviation = c(NA, "TROY"),
    conference = c(NA, "Sun Belt"),
    classification = c(NA, "fbs"),
    color = c(NA, "#8A2432"),
    alternateColor = c(NA, "#FFFFFF"),
    logo_light = c(NA, "https://cdn/logos/500/2653.png"),
    logo_dark = c(NA, "https://cdn/logos-dark/500/2653.png")
  )
  out <- clean_teams(raw)
  expect_equal(nrow(out), 1L)
  expect_equal(out$team, "Troy")
  expect_equal(out$classification, "fbs")
  expect_false(is.na(out$logo_light))
})

test_that("clean_roster keys on a string playerId", {
  # Post-ingest roster: season is stamped from the query year; the endpoint's
  # own `year` (eligibility class) has been renamed to class_year.
  raw <- tibble::tibble(
    id = 55L,
    season = 2018L,
    class_year = 3L,
    team = "USC",
    position = "QB",
    height = 74L,
    weight = 220L,
    homeState = "CA"
  )
  out <- clean_roster(raw)
  expect_equal(out$playerId, "55")
  expect_type(out$season, "integer")
  expect_equal(out$season, 2018L)
  expect_true("weight" %in% names(out))
})

test_that("clean_roster coerces out-of-range placeholder weights to NA", {
  raw <- tibble::tibble(
    id = c(1L, 2L, 3L),
    season = c(2019L, 2019L, 2019L),
    # 0 is the /roster placeholder; 23 is a data-entry error (decision 0009)
    weight = c(0L, 240L, 23L)
  )
  out <- clean_roster(raw)
  expect_true(is.na(out$weight[out$playerId == "1"]))
  expect_equal(out$weight[out$playerId == "2"], 240L)
  expect_true(is.na(out$weight[out$playerId == "3"]))
})
