# Absence-shaped signals from game-level data (issue #51, part 2). Heuristics,
# not labels: the fixtures pin the rules, not any claim about injuries.

seq_fixture <- function(appeared, player = "p1", team = "Alpha") {
  n <- length(appeared)
  tibble::tibble(
    playerId = player,
    season = 2024L,
    team = team,
    gameId = seq_len(n) + 100L,
    week = seq_len(n),
    seasonType = "regular",
    appeared = appeared
  )
}

test_that("classify_absence finds returned and season-ending runs", {
  T <- TRUE
  F <- FALSE
  # Three straight appearances, two missed, then back: a returned gap.
  expect_equal(
    classify_absence(c(T, T, T, F, F, T, T)),
    list(shape = "returned", gap_games = 2L)
  )
  # The run reaches the last game: season-ending.
  expect_equal(
    classify_absence(c(T, T, T, T, F, F, F)),
    list(shape = "season_ending", gap_games = 3L)
  )
  # One missed game is below the minimum gap.
  expect_equal(
    classify_absence(c(T, T, T, F, T, T)),
    list(shape = "none", gap_games = 0L)
  )
  # Never three straight appearances: no signal to read.
  expect_equal(
    classify_absence(c(T, F, T, T, F, F, T)),
    list(shape = "not_observable", gap_games = 0L)
  )
  # A gap before the first streak does not count; season-ending wins over a
  # returned gap earlier in the same season.
  expect_equal(
    classify_absence(c(F, F, T, T, T, F, F, T, T, T, F, F)),
    list(shape = "season_ending", gap_games = 2L)
  )
})

test_that("absence_runs orders games by season type then week", {
  # Rows arrive out of order; week order puts the gap mid-season.
  # A teammate who appears every game keeps all six box scores.
  s <- seq_fixture(c(TRUE, TRUE, TRUE, FALSE, FALSE, TRUE))
  s <- s[c(6, 2, 4, 1, 5, 3), ]
  out <- absence_runs(dplyr::bind_rows(s, seq_fixture(rep(TRUE, 6), "p9")))
  out <- out[out$playerId == "p1", ]
  expect_equal(nrow(out), 1L)
  expect_equal(out$absence_shape, "returned")
  expect_equal(out$box_games, 6L)
  expect_equal(out$games_appeared, 4L)
  expect_true(out$observable)
})

test_that("absence_runs skips team games with no box score", {
  # Games 4 and 5 have no line for anyone on the team (no box score), so they
  # are not misses: the season has no gap.
  s <- dplyr::bind_rows(
    seq_fixture(c(TRUE, TRUE, TRUE, FALSE, FALSE, TRUE), "p1"),
    seq_fixture(c(TRUE, FALSE, TRUE, FALSE, FALSE, TRUE), "p2")
  )
  out <- absence_runs(s)
  expect_equal(out$box_games, c(4L, 4L))
  expect_equal(out$absence_shape[out$playerId == "p1"], "none")
  # A teammate who did appear in a game keeps that game in the sequence.
  s2 <- dplyr::bind_rows(
    seq_fixture(c(TRUE, TRUE, TRUE, FALSE, FALSE, TRUE), "p1"),
    seq_fixture(c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE), "p2")
  )
  out2 <- absence_runs(s2)
  expect_equal(out2$absence_shape[out2$playerId == "p1"], "returned")
})

test_that("absence_runs keeps one row per player-season-team", {
  s <- dplyr::bind_rows(
    seq_fixture(c(TRUE, TRUE, TRUE, FALSE, FALSE), "p1"),
    seq_fixture(c(FALSE, FALSE, FALSE, FALSE, FALSE), "p2"),
    seq_fixture(c(TRUE, TRUE, TRUE, TRUE, TRUE), "p3")
  )
  out <- absence_runs(s)
  expect_equal(nrow(out), 3L)
  expect_equal(
    out$absence_shape[order(out$playerId)],
    c("season_ending", "not_observable", "none")
  )
  expect_equal(out$observable[order(out$playerId)], c(TRUE, FALSE, TRUE))
})

pg_fixture <- function(player, values, column, team = "Alpha") {
  n <- length(values)
  out <- tibble::tibble(
    playerId = player,
    gameId = seq_len(n) + 100L,
    season = 2024L,
    week = seq_len(n),
    seasonType = "regular",
    team = team,
    pass_att = NA_real_,
    rush_car = NA_real_,
    rec = NA_real_,
    tackles = NA_real_
  )
  out[[column]] <- values
  out
}

test_that("usage_decline flags a halving of usage among games appeared", {
  pg <- dplyr::bind_rows(
    # QB: 30 attempts a game, then 5: a decline.
    pg_fixture("qb", c(30, 30, 30, 5, 5, 5), "pass_att"),
    # RB: steady carries: no decline.
    pg_fixture("rb", c(12, 10, 11, 12, 10, 11), "rush_car"),
    # WR below the starter floor in the first half: not observable.
    pg_fixture("wr", c(1, 1, 1, 0, 0, 0), "rec"),
    # LB with too few games: not observable.
    pg_fixture("lb", c(8, 8, 2, 2), "tackles")
  )
  positions <- tibble::tibble(
    playerId = c("qb", "rb", "wr", "lb"),
    season = 2024L,
    team = "Alpha",
    position_group = c("Quarterback", "Running back", "Receiver", "Linebacker")
  )
  out <- usage_decline(pg, positions)
  out <- out[order(out$playerId), ]
  expect_equal(out$playerId, c("lb", "qb", "rb", "wr"))
  expect_equal(out$observable, c(FALSE, TRUE, TRUE, FALSE))
  expect_equal(out$declined, c(FALSE, TRUE, FALSE, FALSE))
  expect_equal(out$first_half[out$playerId == "qb"], 30)
  expect_equal(out$second_half[out$playerId == "qb"], 5)
})

test_that("usage_decline counts a missing stat in a game appeared as zero", {
  # The QB appears in the last three games without a passing line.
  pg <- pg_fixture("qb", c(25, 25, 25, NA, NA, NA), "pass_att")
  positions <- tibble::tibble(
    playerId = "qb",
    season = 2024L,
    team = "Alpha",
    position_group = "Quarterback"
  )
  out <- usage_decline(pg, positions)
  expect_true(out$declined)
  expect_equal(out$second_half, 0)
})

test_that("usage_decline drops positions with no usage stat", {
  pg <- pg_fixture("ol", c(1, 1, 1, 1, 1, 1), "tackles")
  positions <- tibble::tibble(
    playerId = "ol",
    season = 2024L,
    team = "Alpha",
    position_group = "Offensive line"
  )
  expect_equal(nrow(usage_decline(pg, positions)), 0L)
})
