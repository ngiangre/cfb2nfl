games_fixture <- function() {
  tibble::tibble(
    id = c(1L, 2L, 3L),
    season = 2024L,
    week = c(1L, 2L, 3L),
    seasonType = "regular",
    homeTeam = c("Alpha", "Gamma", "Alpha"),
    awayTeam = c("Beta", "Alpha", "Delta"),
    homeClassification = c("fbs", "fbs", "fbs"),
    awayClassification = c("fbs", "fbs", "fcs"),
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

# One row per stat line. p1 has passing + rushing lines in game 1 (must
# collapse to one row); p3 has only a kicking line (must still get a row).
game_player_stats_fixture <- function() {
  tibble::tribble(
    ~gameId , ~team   , ~homeAway , ~category   , ~statType , ~playerId , ~stat   ,
    1L      , "Alpha" , "home"    , "passing"   , "C/ATT"   , "p1"      , "20/30" ,
    1L      , "Alpha" , "home"    , "passing"   , "YDS"     , "p1"      , "250"   ,
    1L      , "Alpha" , "home"    , "passing"   , "TD"      , "p1"      , "2"     ,
    1L      , "Alpha" , "home"    , "passing"   , "INT"     , "p1"      , "1"     ,
    1L      , "Alpha" , "home"    , "rushing"   , "CAR"     , "p1"      , "4"     ,
    1L      , "Alpha" , "home"    , "rushing"   , "YDS"     , "p1"      , "10"    ,
    1L      , "Alpha" , "home"    , "receiving" , "REC"     , "p2"      , "5"     ,
    1L      , "Alpha" , "home"    , "receiving" , "YDS"     , "p2"      , "80"    ,
    1L      , "Alpha" , "home"    , "receiving" , "TD"      , "p2"      , "1"     ,
    1L      , "Alpha" , "home"    , "kicking"   , "FG"      , "p3"      , "2"     ,
    1L      , "Beta"  , "away"    , "defensive" , "TOT"     , "p4"      , "6"     ,
    1L      , "Beta"  , "away"    , "defensive" , "SOLO"    , "p4"      , "3"     ,
    1L      , "Beta"  , "away"    , "defensive" , "SACKS"   , "p4"      , "1.5"   ,
    1L      , "Beta"  , "away"    , "defensive" , "TFL"     , "p4"      , "2"     ,
    2L      , "Alpha" , "away"    , "passing"   , "C/ATT"   , "p1"      , "15/20" ,
    2L      , "Alpha" , "away"    , "passing"   , "YDS"     , "p1"      , "180"   ,
    3L      , "Alpha" , "home"    , "receiving" , "REC"     , "p2"      , "3"     ,
    3L      , "Alpha" , "home"    , "receiving" , "YDS"     , "p2"      , "40"    ,
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

test_that("build_player_game has one row per (playerId, gameId) with a stat line", {
  pg <- build_player_game(game_player_stats_fixture(), games_fixture())

  expect_equal(nrow(pg), 7L)
  expect_false(anyDuplicated(pg[c("playerId", "gameId")]) > 0L)
  # The kicker-only line still gets a row, with usage columns NA.
  k <- pg[pg$playerId == "p3", ]
  expect_equal(nrow(k), 1L)
  expect_true(is.na(k$pass_att) && is.na(k$tackles))
})

test_that("a player's multiple categories in one game collapse to one row", {
  pg <- build_player_game(game_player_stats_fixture(), games_fixture())
  row <- pg[pg$playerId == "p1" & pg$gameId == 1L, ]

  expect_equal(nrow(row), 1L)
  expect_equal(c(row$pass_cmp, row$pass_att), c(20, 30))
  expect_equal(c(row$pass_yds, row$pass_td, row$pass_int), c(250, 2, 1))
  expect_equal(c(row$rush_car, row$rush_yds), c(4, 10))
  # Categories the player has no line in stay NA, not 0.
  expect_true(is.na(row$rec))
})

test_that("sides, opponents and points come from games", {
  pg <- build_player_game(game_player_stats_fixture(), games_fixture())
  beta <- pg[pg$playerId == "p4", ]

  expect_equal(beta$team, "Beta")
  expect_equal(beta$opponent, "Alpha")
  expect_equal(beta$home_away, "away")
  expect_equal(beta$team_points, 20L)
  expect_equal(beta$opponent_points, 30L)
  expect_equal(beta$team_conference, "SEC")
  expect_equal(beta$team_pregame_elo, 1400)
  expect_equal(beta$opponent_pregame_elo, 1500)
})

test_that("neutral sites are flagged and keep the listed sides", {
  pg <- build_player_game(game_player_stats_fixture(), games_fixture())
  neutral <- pg[pg$playerId == "p1" & pg$gameId == 2L, ]

  expect_true(neutral$neutral_site)
  expect_equal(neutral$team, "Alpha")
  expect_equal(neutral$opponent, "Gamma")
  # Alpha is the away side here (Gamma is listed home): its own Elo is 1450.
  expect_equal(neutral$team_pregame_elo, 1450)
  expect_equal(neutral$opponent_pregame_elo, 1600)
  expect_equal(c(neutral$pass_cmp, neutral$pass_att), c(15, 20))
})

test_that("FCS opponents with no Elo stay NA, not dropped", {
  pg <- build_player_game(game_player_stats_fixture(), games_fixture())
  fcs <- pg[pg$playerId == "p2" & pg$gameId == 3L, ]
  delta <- pg[pg$playerId == "p5", ]

  expect_equal(nrow(fcs), 1L)
  expect_true(is.na(fcs$opponent_pregame_elo))
  expect_equal(fcs$team_pregame_elo, 1500)
  expect_true(is.na(delta$team_pregame_elo))
  expect_equal(delta$opponent_pregame_elo, 1500)
})

test_that("team_games counts each team's completed games in the season", {
  pg <- build_player_game(game_player_stats_fixture(), games_fixture())

  # Alpha plays games 1, 2 and 3; Beta plays only game 1.
  expect_true(all(pg$team_games[pg$team == "Alpha"] == 3L))
  expect_true(all(pg$team_games[pg$team == "Beta"] == 1L))
  expect_equal(pg$team_games[pg$playerId == "p5"], 1L)
})

test_that("passing C/ATT splits into completions and attempts", {
  pg <- build_player_game(game_player_stats_fixture(), games_fixture())
  g2 <- pg[pg$playerId == "p1" & pg$gameId == 2L, ]
  expect_equal(c(g2$pass_cmp, g2$pass_att), c(15, 20))
})

test_that("a stat category absent from the input still gets its column", {
  stats <- game_player_stats_fixture() |>
    dplyr::filter(.data$category != "defensive")
  pg <- build_player_game(stats, games_fixture())

  expect_true(all(c("tackles", "sacks", "tfl") %in% names(pg)))
  expect_true(all(is.na(pg$tackles)))
})

test_that("contract_player_game passes on a clean build", {
  stats <- game_player_stats_fixture()
  pg <- build_player_game(stats, games_fixture())
  agent <- contract_player_game(
    pg,
    stats,
    games_fixture(),
    stop_on_fail = FALSE
  )
  expect_true(pointblank::all_passed(agent))
})

test_that("contract_player_game fails on a dropped row (silent row loss)", {
  stats <- game_player_stats_fixture()
  pg <- build_player_game(stats, games_fixture())
  agent <- contract_player_game(
    pg[-1, ],
    stats,
    games_fixture(),
    stop_on_fail = FALSE
  )
  expect_false(pointblank::all_passed(agent))
})

test_that("contract_player_game fails on a duplicated key", {
  stats <- game_player_stats_fixture()
  pg <- build_player_game(stats, games_fixture())
  agent <- contract_player_game(
    rbind(pg, pg[1, ]),
    stats,
    games_fixture(),
    stop_on_fail = FALSE
  )
  expect_false(pointblank::all_passed(agent))
})

test_that("contract_player_game fails on a gameId missing from games", {
  stats <- game_player_stats_fixture()
  pg <- build_player_game(stats, games_fixture())
  agent <- contract_player_game(
    pg,
    stats,
    games_fixture()[-1, ],
    stop_on_fail = FALSE
  )
  expect_false(pointblank::all_passed(agent))
})

test_that("contract_player_game aborts by default when it fails", {
  stats <- game_player_stats_fixture()
  pg <- build_player_game(stats, games_fixture())
  expect_error(
    contract_player_game(pg[-1, ], stats, games_fixture()),
    "data contract failed"
  )
})
