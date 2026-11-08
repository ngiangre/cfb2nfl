# Fixture: two FBS teams (1, 2) and one FCS team (3) across two seasons, plus
# an unplayed game and a D-II game that the export must ignore.
explorer_games_fixture <- function() {
  tibble::tibble(
    id = 1:6,
    season = c(2025L, 2025L, 2025L, 2026L, 2026L, 2026L),
    startDate = c(
      "2025-09-01T19:00:00Z",
      "2025-09-08T19:00:00Z",
      "2025-09-15T19:00:00Z",
      "2026-09-05T19:00:00Z",
      "2026-09-12T19:00:00Z",
      "2026-09-19T19:00:00Z"
    ),
    completed = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
    homeId = c(1L, 2L, 1L, 2L, 4L, 1L),
    awayId = c(2L, 3L, 3L, 1L, 5L, 2L),
    homeConference = c("SEC", "SEC", "SEC", "SEC", "GLIAC", "SEC"),
    awayConference = c("SEC", "SWAC", "SWAC", "SEC", "GLIAC", "SEC"),
    homeClassification = c("fbs", "fbs", "fbs", "fbs", "ii", "fbs"),
    awayClassification = c("fbs", "fcs", "fcs", "fbs", "ii", "fbs"),
    homePoints = c(30L, 41L, 20L, 17L, 10L, NA),
    awayPoints = c(27L, 3L, 20L, 24L, 7L, NA),
    homePostgameElo = c(1610, 1580, 1600, 1560, NA, NA),
    awayPostgameElo = c(1590, NA, NA, 1640, NA, NA)
  )
}

test_that("explorer_default_season is the latest season with a completed game", {
  g <- explorer_games_fixture()
  expect_equal(explorer_default_season(g), 2026L)
  # Preseason: the new season's only game is unplayed, so it falls back.
  g$completed[g$season == 2026L] <- FALSE
  expect_equal(explorer_default_season(g), 2025L)
  g$completed <- FALSE
  expect_error(explorer_default_season(g), "No completed games")
})

test_that("explorer_game_sides gives one row per team per completed game", {
  sides <- explorer_game_sides(explorer_games_fixture())
  expect_equal(nrow(sides), 2L * 5L)
  expect_setequal(
    names(sides),
    c(
      "game_id",
      "season",
      "start",
      "team_id",
      "conference",
      "classification",
      "points",
      "opp_points",
      "elo_post"
    )
  )
  g1 <- sides[sides$game_id == 1L, ]
  expect_equal(g1$points[g1$team_id == 2L], 27L)
  expect_equal(g1$opp_points[g1$team_id == 2L], 30L)
})

explorer_tiers_fixture <- function() {
  tibble::tibble(
    season = c(2025L, 2025L, 2026L, 2026L),
    conference = c("SEC", "SWAC", "SEC", "SWAC"),
    tier = c(3L, 1L, 3L, 1L),
    tier_label = c("Power", "FCS and below", "Power", "FCS and below")
  )
}

test_that("build_explorer_team_season keeps FBS/FCS sides and counts the record", {
  ts <- build_explorer_team_season(
    explorer_games_fixture(),
    explorer_tiers_fixture()
  )
  # Teams 4 and 5 are D-II; game 6 is unplayed. 2025: teams 1, 2, 3;
  # 2026: teams 1, 2.
  expect_false(any(ts$team_id %in% c(4L, 5L)))
  expect_equal(nrow(ts), 5L)
})

test_that("build_explorer_team_season gets W-L-T, end Elo and tier right", {
  ts <- build_explorer_team_season(
    explorer_games_fixture(),
    explorer_tiers_fixture()
  )
  t1 <- ts[ts$team_id == 1L & ts$season == 2025L, ]
  # Team 1 2025: beat 2 (30-27), tied 3 (20-20).
  expect_equal(c(t1$games, t1$wins, t1$losses, t1$ties), c(2L, 1L, 0L, 1L))
  # End Elo = postgame Elo after the last game with an Elo (game 3).
  expect_equal(t1$elo_end, 1600L)
  expect_equal(t1$tier, 3L)
  expect_equal(t1$classification, "fbs")
  t3 <- ts[ts$team_id == 3L, ]
  expect_true(is.na(t3$elo_end)) # FCS: no Elo
  expect_equal(t3$tier_label, "FCS and below")
  expect_equal(ts$wins + ts$losses + ts$ties, ts$games)
  expect_named(
    ts,
    c(
      "team_id",
      "season",
      "conference",
      "classification",
      "tier",
      "tier_label",
      "games",
      "wins",
      "losses",
      "ties",
      "elo_end"
    )
  )
})
