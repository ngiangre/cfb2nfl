# Tests for the movement cards (feature F25, batch movement).

movement_ps_fixture <- function() {
  tibble::tibble(
    playerId = c("a", "b", "c", "d", "e"),
    season = c(2019L, 2019L, 2020L, 2020L, 2020L),
    transferred = c(TRUE, TRUE, FALSE, TRUE, NA),
    transfer_direction = c("up", "down", NA, "lateral", NA),
    tier = c(3L, 1L, 2L, 3L, 1L),
    prev_tier = c(1L, 3L, 2L, 3L, 1L),
    position = c("QB", "?", "RB", "WR", "QB")
  )
}

test_that("transfer_events keeps transferred seasons and labels their direction", {
  ev <- transfer_events(movement_ps_fixture())
  expect_equal(nrow(ev), 3L)
  expect_equal(
    as.character(ev$direction),
    c("To a higher tier", "To a lower tier", "Same tier")
  )
  expect_equal(as.character(ev$from_tier[1]), "FCS and below")
  expect_equal(as.character(ev$to_tier[1]), "Power")
})

test_that("transfer_events groups roster positions and leaves blanks unrecorded", {
  ev <- transfer_events(movement_ps_fixture())
  expect_equal(ev$group, c("Quarterback", "Position not recorded", "Receiver"))
})

test_that("transfer_share_by_season counts only seasons through the cutoff", {
  share <- transfer_share_by_season(movement_ps_fixture(), through = 2019L)
  expect_equal(share$season, 2019L)
  expect_equal(share$seasons, 2L)
  expect_equal(share$transfers, 2L)
  expect_equal(share$share, 1)
})

test_that("transfer_share_by_season reports the share of each season's players", {
  share <- transfer_share_by_season(movement_ps_fixture(), through = 2020L)
  expect_equal(share$seasons, c(2L, 3L))
  expect_equal(share$transfers, c(2L, 1L))
  expect_equal(share$share, c(1, 1 / 3))
})

test_that("position_stay_by_group counts kept groups and drops unrecorded rows", {
  d <- tibble::tibble(
    hs = c(
      "Quarterback",
      "Quarterback",
      "Receiver",
      "Receiver",
      NA,
      "Position not recorded"
    ),
    college = c(
      "Quarterback",
      "Running back",
      "Receiver",
      "Receiver",
      "Receiver",
      "Receiver"
    )
  )
  stay <- position_stay_by_group(d, "hs", "college")
  expect_equal(stay$group, c("Quarterback", "Receiver"))
  expect_equal(stay$recruits, c(2L, 2L))
  expect_equal(stay$stayed, c(1L, 2L))
  expect_equal(stay$share, c(0.5, 1))
})

test_that("position_stay_by_group sorts groups from the lowest share up", {
  d <- tibble::tibble(
    hs = c("Receiver", "Receiver", "Quarterback"),
    college = c("Receiver", "Running back", "Quarterback")
  )
  stay <- position_stay_by_group(d, "hs", "college")
  expect_equal(stay$group, c("Receiver", "Quarterback"))
  expect_equal(stay$share, c(0.5, 1))
})
