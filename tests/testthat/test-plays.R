# Play-by-play tables (CFBD /plays family, decision 0031): flatteners,
# cleaners, the opt-in play-stats flag, and contracts. Fixtures mirror the
# probed response shapes (nested `clock` block, string play/drive ids) without
# hitting the API.

mk_plays_raw <- function() {
  tibble::tibble(
    gameId = c(401L, 401L, 402L),
    driveId = c("4011", "4011", "4021"),
    id = c("40110", "40111", "40210"),
    driveNumber = c(1L, 1L, 1L),
    playNumber = c(1L, 2L, 1L),
    offense = c("LSU", "Alabama", "Auburn"),
    offenseConference = "SEC",
    offenseScore = 0L,
    defense = c("Alabama", "LSU", "Georgia"),
    defenseConference = "SEC",
    defenseScore = 0L,
    home = c("LSU", "LSU", "Georgia"),
    away = c("Alabama", "Alabama", "Auburn"),
    period = 1L,
    clock = data.frame(minutes = c(15L, 14L, 15L), seconds = c(0L, 59L, 0L)),
    offenseTimeouts = 3L,
    defenseTimeouts = 3L,
    yardline = c(35L, 75L, 35L),
    yardsToGoal = c(65L, 75L, 65L),
    down = c(0L, 1L, 0L),
    distance = c(0L, 10L, 0L),
    yardsGained = c(0L, 9L, 0L),
    scoring = FALSE,
    playType = c("Kickoff", "Rush", "Kickoff"),
    playText = c("kickoff", "rush left for 9", "kickoff"),
    ppa = c(NA, 1.25, NA),
    wallclock = "2026-11-07T20:48:31.000Z"
  )
}

mk_play_types <- function() {
  clean_play_types(tibble::tibble(
    id = c(53L, 5L, 999L),
    text = c("Kickoff", "Rush", "Uncategorized"),
    abbreviation = c("K", "RUSH", NA)
  ))
}

mk_play_stat_types <- function() {
  clean_play_stat_types(tibble::tibble(
    id = c(7L, 6L),
    name = c("Rush", "Tackle")
  ))
}

mk_play_stats_raw <- function() {
  tibble::tibble(
    gameId = 401L,
    season = 2026L,
    week = 10L,
    team = c("Alabama", "LSU"),
    conference = "SEC",
    opponent = c("LSU", "Alabama"),
    teamScore = 0L,
    opponentScore = 0L,
    driveId = "4011",
    playId = "40111",
    period = 1L,
    clock = data.frame(minutes = c(14L, 14L), seconds = c(59L, 59L)),
    yardsToGoal = 75L,
    down = 1L,
    distance = 10L,
    athleteId = c("5327659", "5141629"),
    athleteName = c("Rusher", "Tackler"),
    statType = c("Rush", "Tackle"),
    stat = c(9L, 1L)
  )
}

mk_plays_games <- function() {
  tibble::tibble(
    id = c(401L, 402L),
    season = 2026L,
    week = 10L,
    seasonType = "regular",
    completed = TRUE,
    homeClassification = "fbs",
    awayClassification = "fbs"
  )
}

mk_plays <- function() {
  flatten_plays(mk_plays_raw(), 2026L, 10L, "regular") |>
    clean_plays(mk_play_types())
}

test_that("flatten_plays unnests the clock and stamps the pull period", {
  out <- flatten_plays(mk_plays_raw(), 2026L, 10L, "regular")
  expect_false("clock" %in% names(out))
  expect_equal(out$clock_minutes, c(15L, 14L, 15L))
  expect_equal(out$clock_seconds, c(0L, 59L, 0L))
  expect_true(all(out$season == 2026L & out$week == 10L))
  expect_true(all(out$seasonType == "regular"))
  # An empty week (no columns at all) contributes nothing.
  expect_null(flatten_plays(tibble::tibble(), 2026L, 11L, "regular"))
})

test_that("ingest_plays_chunk makes one /plays call and flattens it", {
  withr::local_envvar(CFBD_API_KEY = "test-key")
  seen <- list()
  testthat::local_mocked_bindings(
    cfbd_game_get = function(endpoint, query = list()) {
      seen[[length(seen) + 1L]] <<- list(endpoint = endpoint, query = query)
      mk_plays_raw()
    },
    .env = asNamespace("cfb2nfl")
  )
  out <- ingest_plays_chunk(2026L, 10L, "regular")
  expect_length(seen, 1L)
  expect_equal(seen[[1]]$endpoint, "/plays")
  expect_equal(
    seen[[1]]$query,
    list(year = 2026L, week = 10L, seasonType = "regular")
  )
  expect_equal(out$clock_minutes, c(15L, 14L, 15L))
  expect_true(all(out$week == 10L))
})

test_that("ingest_play_stats_chunk makes one call per game", {
  withr::local_envvar(CFBD_API_KEY = "test-key")
  seen <- list()
  testthat::local_mocked_bindings(
    cfbd_game_get = function(endpoint, query = list()) {
      seen[[length(seen) + 1L]] <<- list(endpoint = endpoint, query = query)
      # A game CFBD has no attribution for returns an empty body.
      if (query$gameId == 402L) {
        return(tibble::tibble())
      }
      mk_play_stats_raw()
    },
    .env = asNamespace("cfb2nfl")
  )
  out <- ingest_play_stats_chunk(c(401L, 402L, 401L))
  expect_length(seen, 2L)
  expect_equal(seen[[1]]$endpoint, "/plays/stats")
  expect_equal(seen[[1]]$query, list(gameId = 401L))
  expect_equal(nrow(out), 2L)
  expect_equal(out$clock_seconds, c(59L, 59L))
})

test_that("clean_plays types the schema and looks up playTypeId", {
  plays <- mk_plays()
  expect_type(plays$id, "character")
  expect_type(plays$gameId, "integer")
  expect_type(plays$driveId, "character")
  expect_type(plays$ppa, "double")
  expect_type(plays$scoring, "logical")
  expect_equal(plays$playTypeId, c(53L, 5L, 53L))
  # A response missing a field (older seasons) still yields the full schema.
  raw <- flatten_plays(mk_plays_raw(), 2010L, 1L, "regular")
  raw$wallclock <- NULL
  old <- clean_plays(raw, mk_play_types())
  expect_named(old, names(plays))
  expect_true(all(is.na(old$wallclock)))
})

test_that("clean_play_stats types the schema; NULL gives the empty table", {
  ps <- clean_play_stats(
    unnest_clock(mk_play_stats_raw()),
    mk_play_stat_types()
  )
  expect_equal(ps$statTypeId, c(7L, 6L))
  expect_type(ps$athleteId, "character")
  expect_type(ps$stat, "double")
  empty <- clean_play_stats(NULL, mk_play_stat_types())
  expect_equal(nrow(empty), 0L)
  expect_named(empty, names(ps))
  expect_type(empty$statTypeId, "integer")
  expect_type(empty$athleteId, "character")
})

test_that("assemble_play_stats replaces pulled games and keeps the rest", {
  types <- mk_play_stat_types()
  path <- withr::local_tempfile(fileext = ".parquet")
  # Nothing pulled, nothing published: the empty typed table.
  seeded <- assemble_play_stats(NULL, types, path)
  expect_equal(nrow(seeded), 0L)
  arrow::write_parquet(seeded, path)
  # A pulled game is added.
  raw <- unnest_clock(mk_play_stats_raw())
  pulled <- assemble_play_stats(raw, types, path)
  expect_equal(nrow(pulled), 2L)
  arrow::write_parquet(pulled, path)
  # Not pulled (or an empty pull): the published file is kept as is.
  expect_equal(nrow(assemble_play_stats(NULL, types, path)), 2L)
  expect_equal(nrow(assemble_play_stats(tibble::tibble(), types, path)), 2L)
  # A new game is appended; a re-pulled game replaces its own rows and the
  # revision count is reported.
  other <- dplyr::mutate(raw, gameId = 402L, playId = "40210")
  revised <- dplyr::mutate(raw, stat = c(12L, 1L))
  expect_message(
    out <- assemble_play_stats(
      dplyr::bind_rows(revised, other),
      types,
      path
    ),
    "Re-pulled 1 game: 2 play-stat rows changed"
  )
  expect_equal(nrow(out), 4L)
  expect_equal(out$stat[out$gameId == 401L], c(12, 1))
})

test_that("play_stats_games_to_pull: new and recent games now, past on demand", {
  d <- as.Date("2026-11-15")
  plays_games <- tibble::tibble(
    season = c(2026L, 2026L, 2026L, 2025L),
    gameId = c(1L, 2L, 3L, 9L)
  )
  games <- tibble::tibble(
    id = c(1L, 2L, 3L, 9L),
    startDate = c(
      "2026-10-31T19:00:00.000Z",
      "2026-11-07T19:00:00.000Z",
      "2026-11-14T19:00:00.000Z",
      "2025-11-08T19:00:00.000Z"
    )
  )
  # Game 1 is published and settled; game 2 is published but inside the
  # re-pull window; game 3 is new.
  expect_equal(
    play_stats_games_to_pull(2026L, plays_games, games, c(1L, 2L), date = d),
    c(2L, 3L)
  )
  # Nothing published yet: the whole season so far.
  expect_equal(
    play_stats_games_to_pull(2026L, plays_games, games, NULL, date = d),
    c(1L, 2L, 3L)
  )
  # A past season only with the backfill flag.
  expect_length(
    play_stats_games_to_pull(2025L, plays_games, games, NULL, date = d),
    0L
  )
  expect_equal(
    play_stats_games_to_pull(
      2025L,
      plays_games,
      games,
      NULL,
      backfill = TRUE,
      date = d
    ),
    9L
  )
})

test_that("play_stats_enabled is opt-in and refuses the full window", {
  withr::local_envvar(CFB2NFL_PLAYS_STATS = NA)
  expect_false(play_stats_enabled(""))
  withr::local_envvar(CFB2NFL_PLAYS_STATS = "true")
  expect_error(play_stats_enabled(""), "full season window")
  expect_true(play_stats_enabled("2025"))
})

test_that("contract_plays passes clean plays and catches holes", {
  games <- mk_plays_games()
  plays <- mk_plays()
  expect_true(pointblank::all_passed(
    contract_plays(plays, games, stop_on_fail = FALSE)
  ))
  # A game the games table does not know.
  stray <- dplyr::mutate(plays, gameId = 999L)
  expect_false(pointblank::all_passed(
    contract_plays(stray, games, stop_on_fail = FALSE)
  ))
  # A played FBS week with no plays.
  more <- dplyr::bind_rows(
    games,
    dplyr::mutate(games[1, ], id = 403L, week = 11L)
  )
  expect_false(plays_cover_played_weeks(plays, more))
  # A play type the dimension does not carry.
  odd <- dplyr::mutate(plays, playTypeId = NA_integer_)
  expect_false(pointblank::all_passed(
    contract_plays(odd, games, stop_on_fail = FALSE)
  ))
  # Out-of-range down.
  bad <- dplyr::mutate(plays, down = 5L)
  expect_error(contract_plays(bad, games), "plays")
})

test_that("contract_play_stats passes when empty and guards the pull", {
  plays <- mk_plays()
  types <- mk_play_stat_types()
  roster <- tibble::tibble(playerId = c("5327659", "5141629"))
  empty <- clean_play_stats(NULL, types)
  expect_true(pointblank::all_passed(
    contract_play_stats(empty, plays, roster, stop_on_fail = FALSE)
  ))
  ps <- clean_play_stats(unnest_clock(mk_play_stats_raw()), types)
  expect_true(pointblank::all_passed(
    contract_play_stats(ps, plays, roster, stop_on_fail = FALSE)
  ))
  # Athlete ids outside the roster namespace.
  expect_false(pointblank::all_passed(
    contract_play_stats(
      ps,
      plays,
      tibble::tibble(playerId = "1"),
      stop_on_fail = FALSE
    )
  ))
  # A game at the 2,000-row cap looks truncated.
  capped <- tibble::tibble(
    gameId = 401L,
    season = 2026L,
    playId = "40111",
    athleteId = "5327659",
    statTypeId = rep(c(7L, 6L), 1000L),
    statType = "Rush",
    stat = 1
  ) |>
    dplyr::mutate(athleteId = as.character(dplyr::row_number()))
  expect_false(pointblank::all_passed(
    contract_play_stats(
      capped,
      plays,
      tibble::tibble(playerId = capped$athleteId),
      stop_on_fail = FALSE
    )
  ))
})

test_that("contract_play_dimension checks keys and size", {
  expect_true(pointblank::all_passed(contract_play_dimension(
    mk_play_types(),
    "text",
    "play_types",
    min_rows = 3L,
    stop_on_fail = FALSE
  )))
  expect_false(pointblank::all_passed(contract_play_dimension(
    mk_play_types(),
    "text",
    "play_types",
    min_rows = 40L,
    stop_on_fail = FALSE
  )))
})

test_that("clean_plays normalizes CFBD's out-of-range situations", {
  raw <- flatten_plays(mk_plays_raw(), 2010L, 1L, "regular")
  raw$down <- c(-1L, 5L, 2L)
  raw$yardsToGoal <- c(65L, 238L, -22L)
  raw$period <- c(0L, 1L, 6L)
  raw$clock_minutes <- c(58L, 14L, 0L)
  out <- clean_plays(raw, mk_play_types())
  # -1 is the pre-2014 code for a non-scrimmage play, the later 0.
  expect_equal(out$down, c(0L, NA, 2L))
  expect_equal(out$yardsToGoal, c(65L, NA, NA))
  expect_equal(out$period, c(NA, 1L, 6L))
  expect_equal(out$clock_minutes, c(NA, 14L, 0L))
})
