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
  expect_equal(p1$draft_class, 2021L)
  expect_true(p1$drafted && p1$eligible)
  expect_equal(p1$draft_round, 2L) # most recent in-window pick wins (decision 0011)
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

test_that("build_team_draft aggregates exits by team, final season, position", {
  cohort <- tibble::tibble(
    playerId = c("1", "2", "3"),
    team = "LSU",
    last_season = 2019L,
    position_group = c("Quarterback", "Quarterback", "Offensive line"),
    drafted = c(TRUE, FALSE, FALSE),
    draft_round = c(1L, NA, NA),
    udfa = c(FALSE, TRUE, FALSE),
    eligible = c(TRUE, TRUE, FALSE)
  )
  ts <- tibble::tibble(
    team = "LSU",
    season = 2019L,
    conference = "SEC",
    tier = 3L,
    tier_label = "Power"
  )
  td <- build_team_draft(cohort, ts)
  qb <- td[td$position_group == "Quarterback", ]
  expect_equal(
    c(qb$n_exits, qb$n_eligible, qb$n_drafted, qb$n_round1, qb$n_udfa),
    c(2L, 2L, 1L, 1L, 1L)
  )
  expect_equal(qb$conference, "SEC")
  expect_equal(nrow(td), 2L)
  expect_equal(sum(td$n_exits), nrow(cohort))
})

test_that("exit_cohort ignores picks outside the draft window (id reuse)", {
  roster <- tibble::tibble(
    playerId = "7",
    season = 2015:2017,
    team = c("A", "B", "B"),
    position = "LB"
  )
  picks <- tibble::tibble(
    playerId = "7",
    year = c(1983L, 2018L),
    round = c(5L, 1L)
  )
  out <- exit_cohort(
    roster,
    picks,
    udfa_ids = character(),
    reused = character(),
    last_roster_season = 2021L
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$team, "B")
  expect_equal(out$draft_class, 2018L)
  expect_equal(out$draft_round, 1L)
})

test_that("mode_chr breaks ties alphabetically and ignores NA", {
  expect_equal(mode_chr(c("b", "a", "b", "a", NA)), "a")
  expect_equal(mode_chr(c(NA_character_, NA_character_)), NA_character_)
})

test_that("build_team_season fills conference for roster-only seasons", {
  f <- team_fixture()
  f$games <- dplyr::bind_rows(
    f$games,
    tibble::tibble(
      season = 2018L,
      completed = TRUE,
      homeTeam = "Tulane",
      homeConference = "SEC",
      homeClassification = "fbs",
      homePoints = 10L,
      awayTeam = "LSU",
      awayConference = "SEC",
      awayClassification = "fbs",
      awayPoints = 7L
    )
  )
  f$tiers <- dplyr::bind_rows(
    f$tiers,
    tibble::tibble(
      season = 2018L,
      conference = "SEC",
      tier = 3L,
      tier_label = "Power"
    )
  )
  # Tulane: games in 2018, roster only in 2019.
  ts <- build_team_season(
    f$roster,
    f$games,
    f$tiers,
    f$player_season,
    f$coaches
  )
  tul19 <- ts[ts$team == "Tulane" & ts$season == 2019L, ]
  expect_equal(tul19$conference, "SEC")
  expect_equal(tul19$tier, 3L)
  expect_true(tul19$conference_filled)
  expect_false(ts$conference_filled[ts$team == "Tulane" & ts$season == 2018L])
  # Games-listed team with no classification falls back to tier 1.
  g <- f$games
  g$awayClassification[g$awayTeam == "Div2 U"] <- NA
  ts2 <- build_team_season(f$roster, g, f$tiers, f$player_season, f$coaches)
  expect_equal(ts2$tier[ts2$team == "Div2 U"], 1L)
})

test_that("build_team_season tiers Notre Dame as Power (decision 0003)", {
  f <- team_fixture()
  f$games <- tibble::tibble(
    season = 2019L,
    completed = TRUE,
    homeTeam = "Notre Dame",
    homeConference = "FBS Independents",
    homeClassification = "fbs",
    homePoints = 30L,
    awayTeam = "Army",
    awayConference = "FBS Independents",
    awayClassification = "fbs",
    awayPoints = 20L
  )
  f$tiers <- tibble::tibble(
    season = 2019L,
    conference = "FBS Independents",
    tier = 2L,
    tier_label = "Group of 5"
  )
  ts <- build_team_season(
    f$roster,
    f$games,
    f$tiers,
    f$player_season,
    f$coaches
  )
  expect_equal(ts$tier[ts$team == "Notre Dame"], 3L)
  expect_equal(ts$tier_label[ts$team == "Notre Dame"], "Power")
  expect_equal(ts$tier[ts$team == "Army"], 2L)
})

test_that("build_team_season does not fill conference for teams that played", {
  f <- team_fixture()
  f$games <- tibble::tibble(
    season = c(2018L, 2019L),
    completed = TRUE,
    homeTeam = "Small College",
    homeConference = c("Conf X", NA),
    homeClassification = c("ii", "ii"),
    homePoints = 10L,
    awayTeam = c("Other A", "Other B"),
    awayConference = c("Conf X", NA),
    awayClassification = "ii",
    awayPoints = 7L
  )
  ts <- build_team_season(
    f$roster,
    f$games,
    f$tiers,
    f$player_season,
    f$coaches
  )
  sc <- ts[ts$team == "Small College" & ts$season == 2019L, ]
  expect_true(is.na(sc$conference))
  expect_false(sc$conference_filled)
  expect_equal(sc$tier, 1L)
})
