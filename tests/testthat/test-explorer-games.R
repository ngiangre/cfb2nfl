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

test_that("explorer_elapsed runs 0-3600 in regulation and gives OT 300 s slots", {
  expect_equal(explorer_elapsed(1L, 15L, 0L, 0), 0L)
  expect_equal(explorer_elapsed(2L, 7L, 30L, 0), 1350L)
  expect_equal(explorer_elapsed(4L, 0L, 0L, 0), 3600L)
  expect_equal(explorer_elapsed(5L, 15L, 0L, 0), 3600L)
  expect_equal(explorer_elapsed(5L, 15L, 0L, 0.5), 3750L)
  expect_equal(explorer_elapsed(6L, 15L, 0L, 0), 3900L)
  expect_true(is.na(explorer_elapsed(3L, NA, 0L, 0)))
  # A bad clock is clamped into its quarter.
  expect_equal(explorer_elapsed(1L, 20L, 0L, 0), 0L)
})

test_that("build_explorer_plays puts every play on the home team's scale", {
  p <- build_explorer_plays(
    explorer_plays_fixture(),
    explorer_games_fixture(),
    explorer_teams_fixture(),
    explorer_play_stats_fixture()
  )
  expect_equal(nrow(p), nrow(explorer_plays_fixture()))
  expect_named(
    p,
    c(
      "season",
      "game_id",
      "play_id",
      "period",
      "clock",
      "elapsed",
      "offense_id",
      "home_score",
      "away_score",
      "home_margin",
      "home_cum_ppa",
      "down",
      "distance",
      "yards_to_goal",
      "play_type",
      "play_text",
      "scoring",
      "turnover",
      "players"
    )
  )
  g1 <- p[p$game_id == 1L, ]
  expect_equal(g1$play_id, c("11", "12", "13", "14", "15"))
  expect_equal(g1$elapsed, c(0L, 270L, 1350L, 3595L, 3600L))
  expect_equal(g1$clock, c("15:00", "10:30", "7:30", "0:05", "OT1"))
  expect_equal(g1$offense_id, c(1L, 1L, 2L, 1L, 2L))
  expect_equal(g1$home_score, c(0L, 7L, 7L, 27L, 27L))
  expect_equal(g1$away_score, c(0L, 0L, 0L, 24L, 24L))
  expect_equal(g1$home_margin, c(0L, 7L, 7L, 3L, 3L))
  # Texas's PPA counts up, Alabama's counts down; NA counts as 0.
  expect_equal(g1$home_cum_ppa, c(0.5, 2.5, 4.0, 4.0, 3.75))
  expect_equal(g1$turnover, c(FALSE, FALSE, TRUE, FALSE, FALSE))
  expect_equal(g1$scoring, c(FALSE, TRUE, FALSE, TRUE, FALSE))
  expect_equal(
    jsonlite::fromJSON(g1$players[2])$name,
    c("Passer One", "Receiver Two")
  )
  expect_true(is.na(g1$players[1]))
  g4 <- p[p$game_id == 4L, ]
  expect_equal(g4$home_cum_ppa, 0.1) # Alabama is home in game 4
})

test_that("write_explorer_team_games writes one JSON file per season", {
  dir <- withr::local_tempdir()
  g <- explorer_games_fixture()
  ts <- build_explorer_team_season(g, explorer_tiers_fixture())
  tg <- build_explorer_team_games(g, ts, play_game_ids = 1L)
  paths <- write_explorer_team_games(tg, dir)
  expect_equal(
    basename(paths),
    c("team_games_2025.json", "team_games_2026.json")
  )
  back <- jsonlite::read_json(paths[[1]], simplifyVector = TRUE)
  expect_equal(nrow(back), sum(tg$season == 2025L))
})

test_that("write_explorer_plays writes season parquet in game order with small row groups", {
  dir <- withr::local_tempdir()
  p <- build_explorer_plays(
    explorer_plays_fixture(),
    explorer_games_fixture(),
    explorer_teams_fixture(),
    explorer_play_stats_fixture()
  )
  paths <- write_explorer_plays(p, dir, chunk_size = 2L)
  expect_equal(basename(paths), c("plays_2025.parquet", "plays_2026.parquet"))
  back <- arrow::read_parquet(paths[[1]])
  expect_equal(back$play_id, c("11", "12", "13", "14", "15"))
  expect_false("season" %in% names(back))
  reader <- arrow::ParquetFileReader$create(paths[[1]])
  expect_equal(reader$num_row_groups, 3L) # 5 rows in chunks of 2
})

explorer_games_assets_fixture <- function() {
  g <- explorer_games_fixture()
  ts <- build_explorer_team_season(g, explorer_tiers_fixture())
  plays <- explorer_plays_fixture()
  list(
    games = g,
    team_season = ts,
    team_games = build_explorer_team_games(g, ts, unique(plays$gameId)),
    plays = plays,
    explorer_plays = build_explorer_plays(
      plays,
      g,
      explorer_teams_fixture(),
      explorer_play_stats_fixture()
    )
  )
}

test_that("contract_explorer_team_games passes, and catches loss and bad results", {
  f <- explorer_games_assets_fixture()
  ok <- function(tg) {
    pointblank::all_passed(contract_explorer_team_games(
      tg,
      f$team_season,
      stop_on_fail = FALSE
    ))
  }
  expect_true(ok(f$team_games))
  expect_false(ok(f$team_games[-1, ]))
  bad <- f$team_games
  bad$result[1] <- "L"
  expect_false(ok(bad))
  bad <- f$team_games
  bad$wp_pre[1] <- 1.5
  expect_false(ok(bad))
  expect_error(
    contract_explorer_team_games(f$team_games[-1, ], f$team_season),
    "explorer_team_games"
  )
})

test_that("contract_explorer_plays passes, and catches loss and orphans", {
  f <- explorer_games_assets_fixture()
  ok <- function(p, games = f$games) {
    pointblank::all_passed(contract_explorer_plays(
      p,
      f$plays,
      games,
      stop_on_fail = FALSE
    ))
  }
  expect_true(ok(f$explorer_plays))
  expect_false(ok(f$explorer_plays[-1, ]))
  expect_false(ok(f$explorer_plays, games = f$games[f$games$id != 4L, ]))
  bad <- f$explorer_plays
  bad$home_margin[2] <- 99L
  expect_false(ok(bad))
})
