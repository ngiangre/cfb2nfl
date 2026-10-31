test_that("position_group maps every roster code to a reader label", {
  codes <- c(
    "QB",
    "RB",
    "FB",
    "WR",
    "TE",
    "T",
    "G",
    "C",
    "OL",
    "OT",
    "DL",
    "DE",
    "DT",
    "NT",
    "EDGE",
    "LB",
    "ILB",
    "OLB",
    "DB",
    "S",
    "CB",
    "PK",
    "P",
    "LS",
    "PR",
    "KR",
    "?",
    "ATH",
    NA
  )
  out <- position_group(codes)
  expect_type(out, "character")
  expect_false(anyNA(out))
  expect_equal(
    out[codes %in% c("T", "G", "C", "OL", "OT")],
    rep("Offensive line", 5)
  )
  expect_equal(out[codes %in% c("FB")], "Running back")
  expect_equal(out[codes %in% c("KR", "PR")], rep("Special teams", 2))
  expect_equal(
    out[is.na(codes) | codes %in% c("?", "ATH")],
    rep("Position not recorded", 3)
  )
  expect_setequal(
    unique(out),
    c(position_group_levels(), "Position not recorded")
  )
})

test_that("team_record counts wins, losses, ties from completed games only", {
  games <- tibble::tibble(
    season = 2019L,
    completed = c(TRUE, TRUE, TRUE, FALSE),
    homeTeam = c("LSU", "Alabama", "LSU", "LSU"),
    homeConference = c("SEC", "SEC", "SEC", "SEC"),
    homeClassification = "fbs",
    homePoints = c(42L, 41L, 20L, NA),
    awayTeam = c("Alabama", "Troy", "Troy", "Troy"),
    awayConference = c("SEC", "Sun Belt", "Sun Belt", "Sun Belt"),
    awayClassification = "fbs",
    awayPoints = c(25L, 46L, 20L, NA)
  )
  rec <- team_record(games)
  lsu <- rec[rec$team == "LSU", ]
  expect_equal(
    c(lsu$games_played, lsu$wins, lsu$losses, lsu$ties),
    c(2L, 1L, 0L, 1L)
  )
  expect_equal(lsu$win_pct, 0.75)
  expect_equal(lsu$conference, "SEC")
  troy <- rec[rec$team == "Troy", ]
  expect_equal(c(troy$wins, troy$losses, troy$ties), c(1L, 0L, 1L))
  expect_equal(nrow(rec), 3L)
  expect_false(anyDuplicated(rec[c("team", "season")]) > 0)
})

test_that("team_record gives NA win_pct when a team has no completed games", {
  games <- tibble::tibble(
    season = 2020L,
    completed = FALSE,
    homeTeam = "A",
    homeConference = "X",
    homeClassification = "fcs",
    homePoints = NA_integer_,
    awayTeam = "B",
    awayConference = "X",
    awayClassification = "fcs",
    awayPoints = NA_integer_
  )
  rec <- team_record(games)
  expect_equal(rec$games_played, c(0L, 0L))
  expect_true(all(is.na(rec$win_pct)))
})

team_fixture <- function() {
  list(
    games = tibble::tibble(
      season = 2019L,
      completed = TRUE,
      homeTeam = c("LSU", "Montana"),
      homeConference = c("SEC", "Big Sky"),
      homeClassification = c("fbs", "fcs"),
      homePoints = c(42L, 30L),
      awayTeam = c("Alabama", "Div2 U"),
      awayConference = c("SEC", "GLIAC"),
      awayClassification = c("fbs", "ii"),
      awayPoints = c(25L, 10L)
    ),
    roster = tibble::tibble(
      playerId = c("1", "2", "3", "4"),
      season = 2019L,
      team = c("LSU", "LSU", "Alabama", "Tulane"),
      position = "QB"
    ),
    tiers = tibble::tibble(
      season = 2019L,
      conference = c("SEC", "Big Sky"),
      tier = c(3L, 1L),
      tier_label = c("Power", "FCS and below")
    ),
    player_season = tibble::tibble(
      playerId = "1",
      season = 2019L,
      team = "LSU"
    ),
    coaches = tibble::tibble(
      school = c("LSU", "LSU"),
      season = 2019L,
      srs = c(NA, 34.2),
      sp_overall = c(NA, 30.1)
    )
  )
}

test_that("build_team_season unions games and roster team-seasons", {
  f <- team_fixture()
  ts <- build_team_season(
    f$roster,
    f$games,
    f$tiers,
    f$player_season,
    f$coaches
  )
  expect_setequal(ts$team, c("LSU", "Alabama", "Montana", "Div2 U", "Tulane"))
  expect_false(anyDuplicated(ts[c("team", "season")]) > 0)
  lsu <- ts[ts$team == "LSU", ]
  expect_equal(c(lsu$n_roster, lsu$n_stat_players), c(2L, 1L))
  expect_true(lsu$has_stat_lines)
  expect_equal(c(lsu$srs, lsu$sp_overall), c(34.2, 30.1))
  expect_equal(lsu$tier_label, "Power")
  # Division II team absent from tiers falls back to tier 1.
  expect_equal(ts$tier[ts$team == "Div2 U"], 1L)
  # Roster-only team (no games) keeps its row with zero games, NA tier.
  tul <- ts[ts$team == "Tulane", ]
  expect_equal(tul$games_played, 0L)
  expect_true(is.na(tul$tier))
  expect_equal(ts$n_roster[ts$team == "Montana"], 0L)
})

test_that("exit_cohort credits the last pre-draft roster team", {
  roster <- tibble::tibble(
    playerId = c("1", "1", "1", "2", "2", "3", "4", "4", "4", "5", "5"),
    season = c(
      2017L,
      2018L,
      2019L,
      2018L,
      2019L,
      2021L,
      2015L,
      2016L,
      2017L,
      2019L,
      2019L
    ),
    team = c(
      "Ohio State",
      "LSU",
      "LSU",
      "Troy",
      "Troy",
      "Troy",
      "Tulane",
      "Tulane",
      "Tulane",
      "Zed",
      "Alpha"
    ),
    position = c(
      "QB",
      "QB",
      "QB",
      "WR",
      "WR",
      "OL",
      "OT",
      "OT",
      "OT",
      "S",
      "CB"
    )
  )
  picks <- tibble::tibble(
    playerId = c("1", "1", NA),
    year = c(2020L, 2021L, 2020L),
    round = c(1L, 2L, 3L)
  )
  out <- exit_cohort(
    roster,
    picks,
    udfa_ids = "4",
    reused = character(),
    last_roster_season = 2021L
  )

  p1 <- out[out$playerId == "1", ]
  expect_equal(p1$team, "LSU")
  expect_equal(p1$last_season, 2019L)
  expect_equal(p1$draft_class, 2020L)
  expect_true(p1$drafted && p1$eligible)
  expect_equal(p1$draft_round, 1L) # earliest pick wins (decision 0011)
  expect_equal(p1$position_group, "Quarterback")

  # Undrafted, 2 seasons, not UDFA: an exit but not eligible.
  p2 <- out[out$playerId == "2", ]
  expect_equal(p2$draft_class, 2020L)
  expect_false(p2$eligible)
  # Still on the latest roster and undrafted: censored, excluded.
  expect_false("3" %in% out$playerId)
  # UDFA lineman with 3 seasons.
  p4 <- out[out$playerId == "4", ]
  expect_true(p4$udfa && p4$eligible && !p4$drafted)
  expect_equal(p4$position_group, "Offensive line")
  # Same-season duplicate resolves to the alphabetical team.
  expect_equal(out$team[out$playerId == "5"], "Alpha")
  expect_false(anyDuplicated(out$playerId) > 0)
})

test_that("exit_cohort drops reused ids", {
  roster <- tibble::tibble(
    playerId = "9",
    season = 2015L,
    team = "A",
    position = "QB"
  )
  out <- exit_cohort(
    roster,
    picks = tibble::tibble(
      playerId = character(),
      year = integer(),
      round = integer()
    ),
    udfa_ids = character(),
    reused = "9",
    last_roster_season = 2020L
  )
  expect_equal(nrow(out), 0L)
})
