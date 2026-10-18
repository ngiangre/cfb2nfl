# Game statistics tables (CFBD /games family): flatten helpers, clean, and
# contracts. Fixtures mirror the real nesting (teams -> categories -> types ->
# athletes / stats) without hitting the API.

mk_game_raw <- function() {
  athlete <- function(id, name, stat) {
    tibble::tibble(id = id, name = name, stat = stat)
  }
  ty <- function(name, athletes) {
    tibble::tibble(name = name, athletes = list(athletes))
  }
  cat <- function(name, types) {
    # `types` is already a list with one (name, athletes) frame per category row.
    tibble::tibble(name = name, types = types)
  }
  team <- function(team, home, pts, cats) {
    tibble::tibble(
      team = team,
      conference = "SEC",
      homeAway = home,
      points = pts,
      categories = list(cats)
    )
  }
  tibble::tibble(
    id = 401540273L,
    teams = list(
      team(
        "Alabama",
        "home",
        31L,
        dplyr::bind_rows(
          cat(
            "passing",
            list(
              ty(
                "YDS",
                athlete(4426688L, "QB One", "300")
              )
            )
          ),
          cat(
            "rushing",
            list(
              ty(
                "CAR",
                athlete(4426688L, "QB One", "5")
              ),
              ty(
                "YDS",
                athlete(4426688L, "QB One", "20")
              )
            )
          )
        )
      ),
      team(
        "Auburn",
        "away",
        30L,
        cat(
          "passing",
          list(ty("YDS", athlete(5550001L, "QB Two", "250")))
        )
      )
    )
  )
}

mk_team_raw <- function() {
  tibble::tibble(
    id = 401540068L,
    teams = list(
      tibble::tibble(
        teamId = c(107L, 108L),
        team = c("Holy Cross", "Harvard"),
        conference = c("Patriot", "Ivy"),
        homeAway = c("home", "away"),
        points = c(28L, 38L),
        stats = list(
          tibble::tibble(
            category = c("rushingTDs", "passingTDs"),
            stat = c("0", "4")
          ),
          tibble::tibble(
            category = c("rushingTDs", "passingTDs"),
            stat = c("2", "2")
          )
        )
      )
    )
  )
}

test_that("flatten_game_player_stats produces one row per athlete-category-statType", {
  flat <- flatten_game_player_stats(mk_game_raw(), 2023L, 5L, "regular")
  # 1 passing stat + 2 rushing stats + 1 passing stat = 4 rows.
  expect_equal(nrow(flat), 4L)
  expect_setequal(unique(flat$category), c("passing", "rushing"))
  expect_setequal(flat$playerId, c("4426688", "5550001"))
  # Period tags attached at flatten time (self-describing table).
  expect_true(all(flat$season == 2023L))
  expect_true(all(flat$week == 5L))
  expect_true(all(flat$seasonType == "regular"))
  # playerId is a string (decision 0003 namespace).
  expect_type(flat$playerId, "character")
  expect_true(all(flat$team[flat$playerId == "4426688"] == "Alabama"))
})

test_that("flatten_game_team_stats produces one row per team-category-stat", {
  flat <- flatten_game_team_stats(mk_team_raw(), 2023L, 5L, "regular")
  expect_equal(nrow(flat), 4L)
  expect_setequal(flat$team, c("Holy Cross", "Harvard"))
  expect_equal(nrow(dplyr::distinct(flat, gameId, team, category)), 4L)
})

test_that("clean_game_player_stats / clean_game_team_stats coerce key types", {
  p <- clean_game_player_stats(
    flatten_game_player_stats(mk_game_raw(), 2023L, 5L, "regular")
  )
  t <- clean_game_team_stats(
    flatten_game_team_stats(mk_team_raw(), 2023L, 5L, "regular")
  )
  expect_type(p$playerId, "character")
  expect_type(p$gameId, "integer")
  expect_type(t$gameId, "integer")
  expect_type(t$teamId, "integer")
  expect_type(p$stat, "character")
})

test_that("game contracts pass well-formed tables and catch bad keys", {
  skip_if_not_installed("pointblank")
  games <- tibble::tibble(
    id = 1L,
    season = 2023L,
    week = 5L,
    seasonType = "regular",
    homeTeam = "Alabama",
    awayTeam = "Auburn",
    homePoints = 31L,
    awayPoints = 30L,
    startDate = "2023-09-30T19:00:00Z",
    completed = TRUE
  )
  expect_true(pointblank::all_passed(contract_games(
    games,
    stop_on_fail = FALSE
  )))

  p <- clean_game_player_stats(
    flatten_game_player_stats(mk_game_raw(), 2023L, 5L, "regular")
  )
  expect_true(
    pointblank::all_passed(contract_game_player_stats(p, stop_on_fail = FALSE))
  )

  t <- clean_game_team_stats(
    flatten_game_team_stats(mk_team_raw(), 2023L, 5L, "regular")
  )
  expect_true(
    pointblank::all_passed(contract_game_team_stats(t, stop_on_fail = FALSE))
  )

  # A repeated (gameId, team, category) pair fails the team-grain contract.
  t_dup <- dplyr::bind_rows(t, dplyr::slice(t, 1))
  expect_false(
    pointblank::all_passed(contract_game_team_stats(
      t_dup,
      stop_on_fail = FALSE
    ))
  )
})

test_that("clean_games coerces the raw game metadata schema", {
  raw <- tibble::tibble(
    id = 401540273,
    season = 2023,
    week = 5,
    seasonType = "regular",
    startDate = "2023-09-30T19:00:00Z",
    startTimeTBD = FALSE,
    completed = TRUE,
    neutralSite = TRUE,
    conferenceGame = FALSE,
    attendance = 42400,
    venueId = 3696,
    venue_name = "Aviva Stadium",
    homeId = 333,
    homeTeam = "Alabama",
    homeClassification = "fbs",
    homeConference = "SEC",
    homePoints = 31,
    homePregameElo = 1900,
    homePostgameElo = 1920,
    homePostgameWinProbability = 0.6,
    awayId = 2,
    awayTeam = "Auburn",
    awayClassification = "fbs",
    awayConference = "SEC",
    awayPoints = 30,
    awayPregameElo = 1800,
    awayPostgameElo = 1790,
    awayPostgameWinProbability = 0.4,
    excitementIndex = 5.2,
    notes = ""
  )
  clean <- clean_games(raw)
  expect_type(clean$id, "integer")
  expect_type(clean$season, "integer")
  expect_type(clean$completed, "logical")
  expect_type(clean$attendance, "double")
  expect_true(pointblank::all_passed(contract_games(
    clean,
    stop_on_fail = FALSE
  )))
})
