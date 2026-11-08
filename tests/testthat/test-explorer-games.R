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
  expect_named(
    tg,
    c(
      "season",
      "week",
      "season_type",
      "start",
      "game_id",
      "team_id",
      "opp_id",
      "opp_name",
      "site",
      "home",
      "points",
      "opp_points",
      "result",
      "elo_pre",
      "elo_post",
      "elo_delta",
      "wp_pre",
      "wp_post",
      "has_plays"
    )
  )
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
