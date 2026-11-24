test_that("explorer_positions lists headline stats for every group", {
  defs <- explorer_positions()
  expect_setequal(
    unique(defs$pos),
    c("QB", "RB", "WR", "TE", "OL", "DL", "LB", "DB", "ST")
  )
  # The line has no box-score stat; it is ranked on roster weight and height.
  expect_equal(defs$category[defs$pos == "OL"], c("roster", "roster"))
  expect_true(all(defs$group %in% position_group_levels()))
  # Keys are unique within a group; a key means the same stat everywhere.
  expect_equal(anyDuplicated(defs[c("pos", "key")]), 0L)
  same <- dplyr::distinct(defs, .data$key, .data$category, .data$stat_type)
  expect_equal(anyDuplicated(same$key), 0L)
  expect_equal(defs$key[defs$pos == "QB"][[1]], "passing_yds")
})

test_that("explorer_player_groups fills an unrecorded position from the nearest season", {
  g <- explorer_player_groups(explorer_player_stats_fixture())
  expect_equal(g$group[g$playerId == "w1" & g$season == 2026L], "Receiver")
  expect_equal(g$group[g$playerId == "o1"], "Offensive line")
  # The position code is filled the same way ("?" is not a position).
  expect_equal(g$position[g$playerId == "w1" & g$season == 2026L], "WR")
  expect_equal(g$position[g$playerId == "o1"], "OT")
})

test_that("build_explorer_player_seasons attaches the roster jersey", {
  ps <- explorer_player_seasons_fixture()
  # The player-team-season roster row wins; a season without a roster row
  # falls back to any jersey the player wore that season.
  q <- ps[ps$player_id == "q1" & ps$season == 2025L, ]
  expect_equal(q$jersey, 7L)
  # A player absent from the roster has NA, and the column survives the
  # per-group write.
  paths <- write_explorer_players(ps, file.path(tempdir(), "explorer-test"))
  d <- arrow::read_parquet(paths[[1]])
  expect_true("jersey" %in% names(d))
  expect_type(d$jersey, "integer")
})

test_that("build_explorer_player_seasons ranks within group and season", {
  ps <- explorer_player_seasons_fixture()
  qb25 <- dplyr::filter(ps, .data$pos == "QB", .data$season == 2025L)
  expect_equal(nrow(qb25), 3L)
  pct <- setNames(qb25$passing_yds_pct, qb25$player_id)
  expect_equal(pct[["q1"]], 100L)
  expect_equal(pct[["q2"]], 0L)
  # Rate stats need 100 attempts: the backup keeps the value, not a rank.
  expect_equal(qb25$passing_ypa[qb25$player_id == "q2"], 7.5)
  expect_true(is.na(qb25$passing_ypa_pct[qb25$player_id == "q2"]))
  # Interceptions are reversed: fewer is better.
  int <- setNames(qb25$passing_int_pct, qb25$player_id)
  expect_gt(int[["q1"]], int[["q3"]])
  # A lone qualifier in a season sits at 100.
  q26 <- dplyr::filter(ps, .data$pos == "QB", .data$season == 2026L)
  expect_equal(q26$passing_yds_pct, 100L)
})

test_that("build_explorer_player_seasons keeps NFL linemen and every stat line", {
  ps <- explorer_player_seasons_fixture()
  # A lineman who never reached the NFL is not listed; one who did is, ranked
  # on roster weight among the NFL linemen of his season.
  expect_false("o1" %in% ps$player_id)
  o2 <- ps[ps$player_id == "o2", ]
  expect_equal(o2$season, c(2024L, 2025L))
  expect_equal(o2$pos, c("OL", "OL"))
  expect_equal(o2$name, c("Omar Tackle", "Omar Tackle"))
  expect_equal(o2$roster_weight, c(315, 315))
  expect_equal(o2$roster_weight_pct[o2$season == 2025L], 100L)
  expect_equal(ps$roster_weight_pct[ps$player_id == "o3"], 0L)
  expect_equal(o2$outcome, c("r1", "r1"))
  expect_equal(sort(unique(ps$pos)), c("OL", "QB", "WR"))
  w <- dplyr::filter(ps, .data$player_id == "w1")
  expect_equal(w$season, c(2025L, 2026L))
  expect_true(all(is.na(w$passing_yds)))
  expect_equal(w$position, c("WR", "WR"))
  # A drafted quarterback's roster season without a stat line is listed,
  # with no stats and his roster name.
  q3 <- ps[ps$player_id == "q3" & ps$season == 2024L, ]
  expect_equal(nrow(q3), 1L)
  expect_true(is.na(q3$passing_yds))
  expect_equal(q3$name, "Quade Other")
  expect_equal(q3$team, "Alabama")
})

test_that("build_explorer_player_seasons joins team id, tier and outcome", {
  ps <- explorer_player_seasons_fixture()
  q1 <- ps[ps$player_id == "q1" & ps$season == 2025L, ]
  expect_equal(q1$team_id, 1L)
  expect_equal(q1$tier, 3L)
  expect_equal(q1$outcome_label, "Still playing")
  # A D-II player has no team id and no outcome row: tier 1, no NFL.
  d2 <- ps[ps$player_id == "d2", ]
  expect_true(is.na(d2$team_id))
  expect_equal(d2$tier, 1L)
  expect_equal(d2$outcome, "none")
  expect_equal(d2$outcome_label, "No NFL")
})

test_that("build_explorer_player_outcomes orders drafted, UDFA, still playing", {
  career_end <- tibble::tibble(
    playerId = c("a", "b", "c", "d", "e"),
    first_season = 2019L,
    last_season = c(2022L, 2022L, 2026L, 2022L, 2022L),
    drafted = c(TRUE, FALSE, FALSE, FALSE, TRUE),
    signed_udfa = c(FALSE, TRUE, FALSE, FALSE, FALSE)
  )
  picks_nfl <- tibble::tibble(
    playerId = c("a", "a", "e"),
    year = c(2023L, 2018L, 2023L),
    round = c(2L, 1L, 5L),
    overall = c(40L, 3L, 150L),
    nflTeam = c("Chicago", "Old", "Denver")
  )
  out <- build_explorer_player_outcomes(career_end, picks_nfl, 2026L)
  expect_equal(out$outcome, c("r2_3", "udfa", "active", "none", "r4_7"))
  # The pick before the first season belongs to someone else (id reuse).
  expect_equal(out$outcome_label[[1]], "Drafted R2 #40 (Chicago)")
  expect_equal(out$outcome_label[[2]], "Signed UDFA")
  expect_true(all(out$outcome %in% explorer_outcome_levels()$outcome))
})

test_that("write_explorer_players writes one file per group with its stats", {
  dir <- withr::local_tempdir()
  ps <- explorer_player_seasons_fixture()
  paths <- write_explorer_players(ps, dir)
  expect_setequal(
    basename(paths),
    paste0(unique(explorer_positions()$pos), ".parquet")
  )
  qb <- arrow::read_parquet(file.path(dir, "players", "QB.parquet"))
  expect_equal(nrow(qb), sum(ps$pos == "QB"))
  expect_true(all(c("passing_yds", "passing_yds_pct") %in% names(qb)))
  expect_false("receiving_yds" %in% names(qb))
  expect_type(qb$season, "integer")
  expect_equal(unique(qb$position), "QB")
  # Names are kept only for teams without an id.
  wr <- arrow::read_parquet(file.path(dir, "players", "WR.parquet"))
  expect_equal(wr$team[wr$player_id == "d2"], "Ferris State")
  expect_true(all(is.na(wr$team[!is.na(wr$team_id)])))
  # A stale file from an old build is removed.
  writeLines("x", file.path(dir, "players", "XX.parquet"))
  write_explorer_players(ps, dir)
  expect_false(file.exists(file.path(dir, "players", "XX.parquet")))
})

test_that("contract_explorer_players passes the fixture and catches loss", {
  dir <- withr::local_tempdir()
  ps <- explorer_player_seasons_fixture()
  paths <- write_explorer_players(ps, dir)
  stats <- explorer_player_stats_fixture()
  expect_true(pointblank::all_passed(
    contract_explorer_players(ps, stats, paths, stop_on_fail = FALSE)
  ))
  # A lost stat row fails; the roster-only rows are extra, not required.
  expect_false(pointblank::all_passed(contract_explorer_players(
    ps[-which(ps$player_id == "q1")[1], ],
    stats,
    paths,
    stop_on_fail = FALSE
  )))
  bad <- ps
  bad$passing_yds_pct[which(ps$player_id == "q1")[1]] <- 101L
  expect_false(pointblank::all_passed(
    contract_explorer_players(bad, stats, paths, stop_on_fail = FALSE)
  ))
  expect_false(pointblank::all_passed(contract_explorer_players(
    ps,
    stats,
    paths,
    max_bytes = 10,
    stop_on_fail = FALSE
  )))
})
