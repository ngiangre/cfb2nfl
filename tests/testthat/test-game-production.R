player_game_fixture <- function() {
  tibble::tibble(
    playerId = c("p1", "p2", "p3", "p4"),
    gameId = c(1L, 2L, 3L, 4L),
    season = 2024L,
    week = c(1L, 2L, 3L, 4L),
    seasonType = "regular",
    team = "A",
    team_conference = "SEC",
    opponent = c("B", "C", "D", "E"),
    opponent_conference = "Big Ten",
    home_away = "home",
    neutral_site = FALSE,
    team_points = 20L,
    opponent_points = 10L,
    team_pregame_elo = 1500,
    opponent_pregame_elo = c(1300, 1500, 1900, NA),
    team_games = 12L,
    pass_cmp = c(10, NA, NA, NA),
    pass_att = c(15, NA, NA, NA),
    pass_yds = c(200, NA, NA, NA),
    pass_td = c(2, NA, NA, NA),
    pass_int = c(0, NA, NA, NA),
    rush_car = c(NA, 5, NA, NA),
    rush_yds = c(NA, 25, NA, NA),
    rush_td = c(NA, 0, NA, NA),
    rec = c(NA, NA, 4, 2),
    rec_yds = c(NA, NA, 60, 30),
    rec_td = c(NA, NA, 1, 0),
    tackles = NA_real_,
    solo_tackles = NA_real_,
    tfl = NA_real_,
    sacks = NA_real_
  )
}

test_that("opponent_elo_band buckets Elo and keeps unrated opponents", {
  expect_equal(
    opponent_elo_band(c(1399, 1400, 1599, 1600, 1800, NA)),
    c(
      "Under 1400",
      "1400 to 1599",
      "1400 to 1599",
      "1600 to 1799",
      "1800 and up",
      "Unrated"
    )
  )
})

test_that("build_game_production has one row per non-NA yardage value", {
  pg <- player_game_fixture()
  gp <- build_game_production(pg)
  expected <- sum(!is.na(pg[c("pass_yds", "rush_yds", "rec_yds")]))
  expect_equal(nrow(gp), expected)
  expect_false(anyDuplicated(gp[c("playerId", "gameId", "stat")]) > 0)
})

test_that("residuals are centred on zero within each season, stat and band", {
  gp <- build_game_production(player_game_fixture())
  # Every (season, stat, band) group with a single player-game has residual 0.
  expect_true(all(abs(gp$residual) < 1e-9 | gp$band_n > 1L))
  # The unrated opponent is its own band, not dropped.
  expect_true("Unrated" %in% gp$opponent_elo_band)
})

test_that("baseline is the group mean and residual is value minus it", {
  gp <- build_game_production(player_game_fixture())
  expect_equal(gp$residual, gp$value - gp$baseline)
  r <- gp[gp$playerId == "p3" & gp$stat == "rec_yds", ]
  expect_equal(r$baseline, 60)
  expect_equal(r$residual, 0)
})

test_that("contract_game_production passes on a clean build", {
  pg <- player_game_fixture()
  agent <- contract_game_production(
    build_game_production(pg),
    pg,
    stop_on_fail = FALSE
  )
  expect_true(pointblank::all_passed(agent))
})

test_that("contract_game_production fails on a dropped row (silent row loss)", {
  pg <- player_game_fixture()
  gp <- build_game_production(pg)
  agent <- contract_game_production(gp[-1, ], pg, stop_on_fail = FALSE)
  expect_false(pointblank::all_passed(agent))
})

test_that("contract_game_production aborts by default when it fails", {
  pg <- player_game_fixture()
  gp <- build_game_production(pg)
  expect_error(contract_game_production(gp[-1, ], pg))
})
