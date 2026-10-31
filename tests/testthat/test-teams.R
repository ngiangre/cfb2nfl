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
