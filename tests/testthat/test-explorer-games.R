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

test_that("build_explorer_plays keeps elapsed non-decreasing and carries stray 0:00 clocks", {
  base <- explorer_plays_fixture()[rep(1L, 7L), ]
  base$id <- sprintf("c%d", 1:7)
  base$gameId <- 1L
  base$driveNumber <- 1L
  base$playNumber <- 1:7
  base$period <- 1L
  base$clock_minutes <- c(4L, 0L, 4L, 0L, 0L, 0L, 0L)
  base$clock_seconds <- c(27L, 0L, 27L, 10L, 11L, 0L, 0L)
  p <- build_explorer_plays(
    base,
    explorer_games_fixture(),
    explorer_teams_fixture(),
    explorer_play_stats_fixture()
  )
  # Stray 0:00 between 4:27 plays carries the previous play's elapsed but
  # keeps its clock text; the 0:11 after 0:10 takes the earlier elapsed; the
  # trailing 0:00 plays are the genuine end of the quarter.
  expect_equal(p$elapsed, c(633L, 633L, 633L, 890L, 890L, 900L, 900L))
  expect_equal(p$clock[2], "0:00")
  expect_false(is.unsorted(p$elapsed, na.rm = TRUE))
  # A stray 0:00 opening a period starts at the period start.
  first <- base[1:3, ]
  first$period <- 2L
  first$clock_minutes <- c(0L, 5L, 4L)
  first$clock_seconds <- c(0L, 0L, 0L)
  p2 <- build_explorer_plays(
    first,
    explorer_games_fixture(),
    explorer_teams_fixture(),
    explorer_play_stats_fixture()
  )
  expect_equal(p2$elapsed, c(900L, 1500L, 1560L))
  # A genuinely missing clock stays untimed.
  na <- base[1:3, ]
  na$clock_minutes[2] <- NA
  p3 <- build_explorer_plays(
    na,
    explorer_games_fixture(),
    explorer_teams_fixture(),
    explorer_play_stats_fixture()
  )
  expect_true(is.na(p3$elapsed[2]))
})

test_that("build_explorer_plays orders plays by period before drive", {
  pl <- explorer_plays_fixture()[rep(1L, 3L), ]
  pl$id <- c("a", "b", "c")
  pl$gameId <- 1L
  pl$driveNumber <- c(1L, 2L, 3L)
  pl$playNumber <- 1L
  # Drive 3 is mislabeled with an early period; time order wins.
  pl$period <- c(1L, 3L, 1L)
  pl$clock_minutes <- c(10L, 5L, 5L)
  pl$clock_seconds <- 0L
  p <- build_explorer_plays(
    pl,
    explorer_games_fixture(),
    explorer_teams_fixture(),
    explorer_play_stats_fixture()
  )
  expect_equal(p$play_id, c("a", "c", "b"))
  expect_false(is.unsorted(p$elapsed))
})

test_that("build_explorer_plays gives one players entry per athlete per play", {
  ps <- rbind(
    explorer_play_stats_fixture(),
    tibble::tibble(
      playId = "12",
      athleteId = "p1",
      athleteName = "Passer One",
      statType = "Attempt"
    )
  )
  p <- build_explorer_plays(
    explorer_plays_fixture(),
    explorer_games_fixture(),
    explorer_teams_fixture(),
    ps
  )
  pl <- jsonlite::fromJSON(p$players[p$play_id == "12"])
  expect_equal(pl$id, c("p1", "p2"))
  expect_equal(pl$stat, c("Completion, Attempt", "Reception"))
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

test_that("write_explorer_plays writes one parquet file per game, in game order", {
  dir <- withr::local_tempdir()
  p <- build_explorer_plays(
    explorer_plays_fixture(),
    explorer_games_fixture(),
    explorer_teams_fixture(),
    explorer_play_stats_fixture()
  )
  root <- write_explorer_plays(p, dir)
  expect_equal(root, file.path(dir, "plays"))
  files <- sort(list.files(root, recursive = TRUE))
  expect_equal(files, c("2025/1.parquet", "2026/4.parquet"))
  back <- arrow::read_parquet(file.path(root, "2025", "1.parquet"))
  expect_equal(back$play_id, c("11", "12", "13", "14", "15"))
  expect_true("game_id" %in% names(back))
  expect_false("season" %in% names(back))
  expect_equal(
    nrow(arrow::read_parquet(file.path(root, "2026", "4.parquet"))),
    1L
  )
})

test_that("write_explorer_plays removes stale per-season files and old game files", {
  dir <- withr::local_tempdir()
  p <- build_explorer_plays(
    explorer_plays_fixture(),
    explorer_games_fixture(),
    explorer_teams_fixture(),
    explorer_play_stats_fixture()
  )
  dir.create(file.path(dir, "plays", "2025"), recursive = TRUE)
  writeLines("old", file.path(dir, "plays", "2025", "99.parquet"))
  writeLines("old", file.path(dir, "plays_2025.parquet"))
  write_explorer_plays(p, dir)
  expect_false(file.exists(file.path(dir, "plays", "2025", "99.parquet")))
  expect_false(file.exists(file.path(dir, "plays_2025.parquet")))
  expect_equal(
    sort(list.files(file.path(dir, "plays"), recursive = TRUE)),
    c("2025/1.parquet", "2026/4.parquet")
  )
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

test_that("contract_explorer_team_games caps each season file at the gzip budget", {
  f <- explorer_games_assets_fixture()
  ok <- function(limit) {
    pointblank::all_passed(contract_explorer_team_games(
      f$team_games,
      f$team_season,
      max_gzip_bytes = limit,
      stop_on_fail = FALSE
    ))
  }
  expect_true(ok(150000L))
  expect_false(ok(10L))
})

test_that("contract_explorer_plays_files passes on one file per game", {
  f <- explorer_games_assets_fixture()
  dir <- withr::local_tempdir()
  root <- write_explorer_plays(f$explorer_plays, dir)
  expect_true(pointblank::all_passed(contract_explorer_plays_files(
    root,
    f$explorer_plays,
    stop_on_fail = FALSE
  )))
})

test_that("contract_explorer_plays_files catches missing and extra game files", {
  f <- explorer_games_assets_fixture()
  dir <- withr::local_tempdir()
  root <- write_explorer_plays(f$explorer_plays, dir)
  ok <- function() {
    pointblank::all_passed(contract_explorer_plays_files(
      root,
      f$explorer_plays,
      stop_on_fail = FALSE
    ))
  }
  file.remove(file.path(root, "2026", "4.parquet"))
  expect_false(ok())
  expect_error(
    contract_explorer_plays_files(root, f$explorer_plays),
    "explorer_plays_files"
  )
  write_explorer_plays(f$explorer_plays, dir)
  writeLines("x", file.path(root, "2025", "77.parquet"))
  expect_false(ok())
})
