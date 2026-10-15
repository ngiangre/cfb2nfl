test_that("add_change_features derives transfer, direction, and coach changes", {
  ps <- tibble::tibble(
    playerId = c("1", "1", "2"),
    season = c(2020L, 2021L, 2021L),
    team = c("Boise State", "USC", "Alabama"),
    tier = c(2L, 3L, 3L),
    coach_id = c(10L, 20L, 30L)
  )
  out <- add_change_features(ps)

  # Player 1's second season: transferred up, coach changed, did not follow.
  row <- out[out$playerId == "1" & out$season == 2021L, ]
  expect_true(row$transferred)
  expect_equal(row$transfer_direction, "up")
  expect_true(row$hc_changed)
  expect_false(row$followed_coach)

  # First observed season has no prior: not a transfer.
  first <- out[out$playerId == "1" & out$season == 2020L, ]
  expect_false(first$transferred)
  expect_true(is.na(first$transfer_direction))
})

test_that("followed_coach is TRUE when a transfer keeps the same head coach", {
  ps <- tibble::tibble(
    playerId = c("3", "3"),
    season = c(2022L, 2023L),
    team = c("Washington State", "Miami"),
    tier = c(2L, 3L),
    coach_id = c(99L, 99L)
  )
  out <- add_change_features(ps)
  row <- out[out$season == 2023L, ]
  expect_true(row$transferred)
  expect_true(row$followed_coach)
})

test_that("career_summary counts seasons, gaps, and transfers per player", {
  roster <- tibble::tibble(
    playerId = c("1", "1", "1", "2", "2", "3"),
    season = c(2018L, 2019L, 2021L, 2019L, 2020L, 2022L),
    team = c("IU", "IU", "Miami", "IU", "IU", "IU")
  )
  out <- career_summary(roster)
  expect_equal(nrow(out), 3L)
  p1 <- out[out$playerId == "1", ]
  expect_equal(p1$seasons, 3L)
  expect_equal(p1$first_season, 2018L)
  expect_equal(p1$last_season, 2021L)
  expect_equal(p1$gap_seasons, 1L)
  expect_equal(p1$transfers, 1L)
  expect_equal(out$transfers[out$playerId == "2"], 0L)
})

test_that("career_summary handles duplicate player-season rows", {
  roster <- tibble::tibble(
    playerId = rep("1", 3),
    season = rep(2020L, 3),
    team = rep("IU", 3)
  )
  out <- career_summary(roster)
  expect_equal(out$seasons, 1L)
  expect_equal(out$transfers, 0L)
})

test_that("add_roster_weight attaches roster weight by player-season", {
  ps <- tibble::tibble(
    playerId = c("1", "1", "2"),
    season = c(2020L, 2021L, 2021L)
  )
  roster <- tibble::tibble(
    playerId = c("1", "1"),
    season = c(2020L, 2021L),
    weight = c(210L, 225L)
  )
  out <- add_roster_weight(ps, roster)
  expect_equal(out$weight[out$playerId == "1" & out$season == 2021L], 225L)
  expect_true(is.na(out$weight[out$playerId == "2"]))
})

test_that("transfer_counts aggregates by season and direction", {
  ps <- tibble::tibble(
    playerId = c("1", "1", "2", "2"),
    season = c(2021L, 2022L, 2021L, 2022L),
    team = c("IU", "Miami", "IU", "OSU"),
    tier = c(2L, 3L, 3L, 3L),
    coach_id = c(1L, 2L, 1L, 3L)
  )
  out <- add_change_features(ps) |> transfer_counts()
  expect_equal(nrow(out), 2L)
  up <- out[out$season == 2022L & out$transfer_direction == "up", ]
  expect_equal(up$n_transfers, 1L)
  lateral <- out[out$season == 2022L & out$transfer_direction == "lateral", ]
  expect_equal(lateral$n_transfers, 1L)
})

test_that("transfer_rate computes the share of careers with a transfer", {
  career <- tibble::tibble(
    playerId = c("1", "2", "3", "4"),
    transfers = c(1L, 0L, 2L, 0L)
  )
  out <- transfer_rate(career)
  expect_equal(out$players, 4L)
  expect_equal(out$transferred, 2L)
  expect_equal(out$share, 0.5)
})

test_that("flag_redshirt marks no-stat seasons that the player returned from", {
  roster <- tibble::tibble(
    playerId = c("1", "1", "1", "2", "2"),
    season = c(2021L, 2022L, 2023L, 2022L, 2023L),
    class_year = c(1L, 2L, 3L, 4L, 5L)
  )
  stats <- tibble::tibble(
    playerId = c("1", "1", "2"),
    season = c(2022L, 2023L, 2022L)
  )
  out <- flag_redshirt(roster, stats)
  # Player 1: 2021 has no stats and a later season -> redshirt-shaped;
  # 2023 (final season) has no stats but is NOT flagged.
  p1 <- out[out$playerId == "1", ]
  expect_equal(p1$redshirt_season[p1$season == 2021L], TRUE)
  expect_equal(p1$redshirt_season[p1$season == 2023L], FALSE)
  expect_true(all(p1$redshirt_career))
  # Player 2: every roster season has stats.
  p2 <- out[out$playerId == "2", ]
  expect_false(any(p2$redshirt_season))
  expect_false(any(p2$redshirt_career))
  # Fifth-year signal: player 2 reached class_year 5.
  expect_true(all(p2$fifth_year_career))
  expect_false(any(p1$fifth_year_career))
})

test_that("flag_redshirt tolerates missing class_year", {
  roster <- tibble::tibble(
    playerId = c("1", "1"),
    season = c(2021L, 2022L),
    class_year = c(NA_integer_, 2L)
  )
  stats <- tibble::tibble(playerId = "1", season = 2022L)
  out <- flag_redshirt(roster, stats)
  expect_equal(out$redshirt_season[out$season == 2021L], TRUE)
  expect_equal(out$fifth_year_career[1], FALSE)
})
