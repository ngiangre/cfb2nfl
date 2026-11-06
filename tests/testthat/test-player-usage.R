# Playing-time table (issue #50, decision 0038). Fixture: Alpha plays games 1
# (home), 2 (away) and 3 (home), so team_games = 3; Beta and Delta play once.

usage_games_fixture <- function() {
  tibble::tibble(
    id = c(1L, 2L, 3L),
    season = 2024L,
    week = c(1L, 2L, 3L),
    seasonType = "regular",
    homeTeam = c("Alpha", "Gamma", "Alpha"),
    awayTeam = c("Beta", "Alpha", "Delta"),
    homeClassification = "fbs",
    awayClassification = "fbs",
    homeConference = c("SEC", "Big Ten", "SEC"),
    awayConference = c("SEC", "SEC", NA_character_),
    homePoints = c(30L, 10L, 20L),
    awayPoints = c(20L, 7L, 3L),
    homePregameElo = c(1500, 1600, 1500),
    awayPregameElo = c(1400, 1450, NA),
    neutralSite = c(FALSE, TRUE, FALSE),
    completed = TRUE
  )
}

usage_stats_fixture <- function() {
  tibble::tribble(
    ~gameId , ~team   , ~homeAway , ~category   , ~statType , ~playerId , ~stat   ,
    1L      , "Alpha" , "home"    , "passing"   , "C/ATT"   , "p1"      , "20/30" ,
    1L      , "Alpha" , "home"    , "passing"   , "YDS"     , "p1"      , "250"   ,
    1L      , "Alpha" , "home"    , "rushing"   , "CAR"     , "p1"      , "4"     ,
    1L      , "Alpha" , "home"    , "receiving" , "REC"     , "p2"      , "5"     ,
    1L      , "Alpha" , "home"    , "kicking"   , "FG"      , "p3"      , "2"     ,
    1L      , "Beta"  , "away"    , "defensive" , "TOT"     , "p4"      , "6"     ,
    2L      , "Alpha" , "away"    , "passing"   , "C/ATT"   , "p1"      , "15/20" ,
    2L      , "Alpha" , "away"    , "rushing"   , "CAR"     , "p1"      , "0"     ,
    3L      , "Alpha" , "home"    , "receiving" , "REC"     , "p2"      , "3"     ,
    3L      , "Delta" , "away"    , "receiving" , "REC"     , "p5"      , "2"
  ) |>
    dplyr::mutate(
      gameId = as.integer(.data$gameId),
      season = 2024L,
      week = as.integer(match(.data$gameId, c(1L, 2L, 3L))),
      seasonType = "regular",
      conference = NA_character_,
      points = 0L,
      player = .data$playerId
    )
}

usage_roster_fixture <- function() {
  tibble::tibble(
    playerId = c("p1", "p2", "p3", "p4", "p6"),
    season = 2024L,
    team = c("Alpha", "Alpha", "Alpha", "Beta", "Alpha"),
    position = c("QB", "WR", "K", "DT", "OT"),
    class_year = c(2L, 3L, 4L, 1L, 2L)
  )
}

usage_fixture <- function() {
  pg <- build_player_game(usage_stats_fixture(), usage_games_fixture())
  list(
    pg = pg,
    games = usage_games_fixture(),
    roster = usage_roster_fixture(),
    usage = build_player_usage(
      pg,
      usage_roster_fixture(),
      usage_games_fixture()
    )
  )
}

usage_row <- function(usage, id, team = NULL) {
  out <- usage[usage$playerId == id, ]
  if (!is.null(team)) {
    out <- out[out$team == team, ]
  }
  out
}

test_that("team_game_schedule has one row per team per completed game", {
  sched <- team_game_schedule(usage_games_fixture())
  expect_equal(nrow(sched), 6L)
  expect_equal(sum(sched$team == "Alpha"), 3L)
  expect_equal(sum(sched$team == "Gamma"), 1L)
})

test_that("team_game_schedule counts match team_record games_played", {
  games <- usage_games_fixture()
  sched <- team_game_schedule(games)
  rec <- team_record(games)
  counted <- dplyr::count(sched, .data$season, .data$team, name = "n")
  joined <- dplyr::inner_join(counted, rec, by = c("season", "team"))
  expect_equal(joined$n, joined$games_played)
})

test_that("appearance sequence is complete and flags every stat-line game", {
  fx <- usage_fixture()
  seq <- player_appearance_sequence(fx$pg, fx$roster, fx$games)
  # Universe: Alpha has 4 players (p1, p2, p3, p6) over 3 games, Beta 1 over
  # 1 game (p4), Delta 1 over 1 game (p5).
  expect_equal(nrow(seq), 4L * 3L + 1L + 1L)
  expect_equal(sum(seq$appeared), nrow(fx$pg))
  p1 <- seq[seq$playerId == "p1", ]
  expect_equal(p1$appeared, c(TRUE, TRUE, FALSE))
  expect_equal(p1$seasonType, rep("regular", 3))
})

test_that("build_player_usage gives games appeared over team games", {
  fx <- usage_fixture()
  u <- fx$usage
  p1 <- usage_row(u, "p1", "Alpha")
  expect_equal(p1$team_games, 3L)
  expect_equal(p1$games_appeared, 2L)
  expect_equal(p1$appearance_rate, 2 / 3)
  expect_equal(usage_row(u, "p3")$games_appeared, 1L)
  expect_equal(usage_row(u, "p4")$appearance_rate, 1)
})

test_that("roster-only players keep a row with zero appearances", {
  u <- usage_fixture()$usage
  p6 <- usage_row(u, "p6")
  expect_equal(p6$games_appeared, 0L)
  expect_equal(p6$team_games, 3L)
  expect_equal(p6$appearance_rate, 0)
  expect_true(is.na(p6$pass_att_pg))
  expect_equal(p6$position_group, "Offensive line")
})

test_that("stat-line players off the roster are kept with on_roster FALSE", {
  u <- usage_fixture()$usage
  p5 <- usage_row(u, "p5")
  expect_equal(nrow(p5), 1L)
  expect_false(p5$on_roster)
  expect_true(is.na(p5$position_group))
  expect_true(is.na(p5$class_year))
  expect_equal(p5$games_appeared, 1L)
})

test_that("per-game usage divides the total by games appeared", {
  u <- usage_fixture()$usage
  p1 <- usage_row(u, "p1", "Alpha")
  # Pass attempts 30 + 20 over 2 games appeared; carries 4 + 0.
  expect_equal(p1$pass_att_pg, 25)
  expect_equal(p1$rush_car_pg, 2)
  # A stat absent from every appeared game is 0 per game, not NA.
  expect_equal(p1$rec_pg, 0)
  p2 <- usage_row(u, "p2")
  expect_equal(p2$rec_pg, 4)
  expect_equal(usage_row(u, "p4")$tackles_pg, 6)
})

test_that("regular-season columns count regular-season games only", {
  u <- usage_fixture()$usage
  p2 <- usage_row(u, "p2")
  expect_equal(p2$reg_team_games, 3L)
  expect_equal(p2$reg_games_appeared, 2L)
  expect_equal(p2$reg_appearance_rate, 2 / 3)
})

test_that("contract_player_usage passes on a clean build", {
  fx <- usage_fixture()
  agent <- contract_player_usage(
    fx$usage,
    fx$pg,
    fx$games,
    stop_on_fail = FALSE
  )
  expect_true(pointblank::all_passed(agent))
})

test_that("contract_player_usage fails when games appeared exceeds team games", {
  fx <- usage_fixture()
  bad <- fx$usage
  bad$games_appeared[1] <- bad$team_games[1] + 1L
  agent <- contract_player_usage(bad, fx$pg, fx$games, stop_on_fail = FALSE)
  expect_false(pointblank::all_passed(agent))
})

test_that("contract_player_usage fails on a dropped player-season (silent row loss)", {
  fx <- usage_fixture()
  dropped <- fx$usage[fx$usage$playerId != "p1", ]
  agent <- contract_player_usage(dropped, fx$pg, fx$games, stop_on_fail = FALSE)
  expect_false(pointblank::all_passed(agent))
})

test_that("contract_player_usage fails on a duplicated key", {
  fx <- usage_fixture()
  dup <- dplyr::bind_rows(fx$usage, fx$usage[1, ])
  agent <- contract_player_usage(dup, fx$pg, fx$games, stop_on_fail = FALSE)
  expect_false(pointblank::all_passed(agent))
})

test_that("contract_player_usage aborts by default when it fails", {
  fx <- usage_fixture()
  bad <- fx$usage
  bad$games_appeared[1] <- bad$team_games[1] + 1L
  expect_error(contract_player_usage(bad, fx$pg, fx$games))
})
