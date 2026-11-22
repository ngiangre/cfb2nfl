# Play-level NFL tables (feature F23): play-by-play, participation, snap
# counts and weekly rosters, conformed to their dictionaries so an nflverse
# schema change cannot break the season splice.

dict_cols <- function(dataset) {
  dict <- yaml::read_yaml(app_sys("dict", paste0(dataset, ".yml")))
  vapply(dict$columns, \(col) col$name, character(1))
}

test_that("conform_to_dict adds, drops and types columns to the dictionary", {
  raw <- tibble::tibble(
    game_id = "2025_01_ARI_NO",
    play_id = 40, # double upstream; the dictionary says double
    season = 2025, # double here, int32 in the dictionary
    epa = "0.5", # mistyped upstream
    brand_new_column = 1
  )
  expect_message(
    out <- conform_to_dict(raw, "nfl_pbp"),
    "brand_new_column"
  )
  expect_identical(names(out), dict_cols("nfl_pbp"))
  expect_identical(out$season, 2025L)
  expect_identical(out$epa, 0.5)
  # A column nflverse stopped shipping is kept, as a typed NA.
  expect_true(is.na(out$passer_player_id))
  expect_type(out$passer_player_id, "character")
})

test_that("conform_to_dict handles an empty pull", {
  out <- conform_to_dict(tibble::tibble(), "nfl_snap_counts")
  expect_identical(nrow(out), 0L)
  expect_identical(names(out), dict_cols("nfl_snap_counts"))
})

test_that("clean_nfl_pbp keeps one row per play", {
  raw <- tibble::tibble(
    game_id = c("2025_01_ARI_NO", "2025_01_ARI_NO", "2025_01_ARI_NO"),
    play_id = c(1, 40, 40),
    season = 2025L,
    season_type = "REG",
    epa = c(NA, 0.2, 0.2)
  )
  out <- suppressMessages(clean_nfl_pbp(raw))
  expect_identical(nrow(out), 2L)
  expect_false(anyDuplicated(out[c("game_id", "play_id")]) > 0)
})

test_that("clean_nfl_participation derives the season from the game id", {
  raw <- tibble::tibble(
    nflverse_game_id = c("2022_01_BUF_LA", "2025_18_NO_ATL"),
    play_id = c(40L, 55L),
    offense_players = c("00-0034857;00-0036355", NA)
  )
  out <- suppressMessages(clean_nfl_participation(raw))
  expect_identical(out$season, c(2022L, 2025L))
  expect_identical(names(out), dict_cols("nfl_participation"))
})

test_that("clean_nfl_snap_counts drops rows with no player id", {
  raw <- tibble::tibble(
    game_id = "2025_01_ARI_NO",
    season = 2025L,
    pfr_player_id = c("SmitJo00", NA),
    offense_snaps = c(60, 3),
    offense_pct = c(0.9, 0.05)
  )
  out <- suppressMessages(clean_nfl_snap_counts(raw))
  expect_identical(out$pfr_player_id, "SmitJo00")
})

test_that("clean_nfl_rosters_weekly drops id-less rows and keeps team moves", {
  raw <- tibble::tibble(
    season = 2025L,
    week = c(8L, 8L, 8L, 8L),
    team = c("NYJ", "DAL", "NYJ", "NYJ"),
    gsis_id = c("00-0030000", "00-0030000", NA, ""),
    status = c("TRD", "ACT", "ACT", "TRD"),
    jersey_number = c("12", "7", "3", "12")
  )
  out <- suppressMessages(clean_nfl_rosters_weekly(raw))
  # The traded player keeps a row for each team in the week of the move;
  # an empty id (nflverse ships a few) is as unlinkable as NA.
  expect_identical(nrow(out), 2L)
  expect_setequal(out$team, c("NYJ", "DAL"))
  expect_type(out$jersey_number, "integer")
})

test_that("nfl_published_seasons drops seasons nflverse has not started", {
  testthat::local_mocked_bindings(
    most_recent_season = function(...) 2026L,
    .package = "nflreadr"
  )
  expect_identical(nfl_published_seasons(2025:2027), 2025:2026)
})

test_that("ingest_nfl_participation skips a season nflverse has not published", {
  testthat::local_mocked_bindings(
    most_recent_season = function(...) 2026L,
    load_participation = function(seasons, ...) {
      if (seasons == 2026L) {
        return(tibble::tibble())
      }
      tibble::tibble(
        nflverse_game_id = paste0(seasons, "_01_A_B"),
        play_id = 1L
      )
    },
    .package = "nflreadr"
  )
  expect_message(out <- ingest_nfl_participation(2025:2026), "2026")
  expect_identical(nrow(out), 1L)
})

# ---- contracts --------------------------------------------------------------

pbp_fixture <- function() {
  tibble::tibble(
    game_id = c("2025_01_ARI_NO", "2025_01_ARI_NO"),
    play_id = c(1, 40),
    season = 2025L,
    season_type = "REG",
    epa = c(NA, 0.4),
    passer_player_id = c(NA, "00-0035228")
  ) |>
    conform_to_dict("nfl_pbp")
}

test_that("contract_nfl_pbp passes clean plays and catches bad ones", {
  expect_true(pointblank::all_passed(
    contract_nfl_pbp(pbp_fixture(), stop_on_fail = FALSE)
  ))
  dup <- pbp_fixture()[c(1, 2, 2), ]
  expect_false(pointblank::all_passed(
    contract_nfl_pbp(dup, stop_on_fail = FALSE)
  ))
  bad_id <- pbp_fixture()
  bad_id$passer_player_id[2] <- "Burrow"
  expect_false(pointblank::all_passed(
    contract_nfl_pbp(bad_id, stop_on_fail = FALSE)
  ))
  early <- pbp_fixture()
  early$season <- 2021L
  expect_error(contract_nfl_pbp(early), "nfl_pbp")
})

test_that("contract_nfl_snap_counts bounds the snap shares", {
  snaps <- conform_to_dict(
    tibble::tibble(
      game_id = "2025_01_ARI_NO",
      season = 2025L,
      game_type = "REG",
      pfr_player_id = c("A", "B"),
      offense_snaps = c(60, 0),
      offense_pct = c(0.95, 0)
    ),
    "nfl_snap_counts"
  )
  expect_true(pointblank::all_passed(
    contract_nfl_snap_counts(snaps, stop_on_fail = FALSE)
  ))
  snaps$offense_pct[1] <- 1.5
  expect_false(pointblank::all_passed(
    contract_nfl_snap_counts(snaps, stop_on_fail = FALSE)
  ))
})

test_that("contract_nfl_rosters_weekly checks the key and status codes", {
  weekly <- conform_to_dict(
    tibble::tibble(
      season = 2025L,
      week = c(1L, 2L),
      game_type = "REG",
      team = "NYJ",
      gsis_id = "00-0030000",
      status = c("ACT", "RES")
    ),
    "nfl_rosters_weekly"
  )
  expect_true(pointblank::all_passed(
    contract_nfl_rosters_weekly(weekly, stop_on_fail = FALSE)
  ))
  weekly$status[2] <- "injured"
  expect_false(pointblank::all_passed(
    contract_nfl_rosters_weekly(weekly, stop_on_fail = FALSE)
  ))
})

test_that("contract_nfl_participation checks the key and season", {
  part <- suppressMessages(clean_nfl_participation(tibble::tibble(
    nflverse_game_id = c("2024_01_BUF_LA", "2024_01_BUF_LA"),
    play_id = c(40L, 55L)
  )))
  expect_true(pointblank::all_passed(
    contract_nfl_participation(part, stop_on_fail = FALSE)
  ))
  expect_false(pointblank::all_passed(
    contract_nfl_participation(part[c(1, 1), ], stop_on_fail = FALSE)
  ))
})

test_that("contract_nfl_bridge fails when entrants or snaps stop linking", {
  outcomes <- tibble::tibble(
    playerId = c("1", "1", "2", "3", "4"),
    draft_year = c(2022L, 2023L, 2023L, 2024L, 2021L),
    outcome_nfl_entry_d = c(FALSE, TRUE, TRUE, TRUE, TRUE),
    gsis_id = c("00-0000001", "00-0000001", "00-0000002", NA, "00-0000009")
  )
  weekly <- tibble::tibble(gsis_id = c("00-0000001", "00-0000002"))
  snaps <- tibble::tibble(pfr_player_id = c("A", "B", "A"))
  players <- tibble::tibble(pfr_id = c("A", "B"), gsis_id = c("x", "y"))

  agent <- contract_nfl_bridge(
    outcomes,
    weekly,
    snaps,
    players,
    stop_on_fail = FALSE
  )
  expect_true(pointblank::all_passed(agent))
  # Entrants without a gsis_id are counted, not failed (player "3").
  expect_identical(
    nfl_bridge_coverage(outcomes, weekly, snaps, players)$n_no_gsis,
    1L
  )

  expect_false(pointblank::all_passed(contract_nfl_bridge(
    outcomes,
    weekly[1, ],
    snaps,
    players,
    stop_on_fail = FALSE
  )))
  expect_false(pointblank::all_passed(contract_nfl_bridge(
    outcomes,
    weekly,
    snaps,
    players[1, ],
    stop_on_fail = FALSE
  )))
})
