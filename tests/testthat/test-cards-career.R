test_that("signature_positions takes each player's most frequent QB/RB/WR position", {
  roster <- tibble::tibble(
    playerId = c("1", "1", "1", "2", "3"),
    season = c(2019L, 2020L, 2021L, 2019L, 2019L),
    position = c("WR", "QB", "QB", "TE", "RB")
  )
  out <- signature_positions(roster)
  expect_equal(out$playerId, c("1", "3"))
  expect_equal(out$group, c("Quarterback", "Running back"))
})

test_that("signature_season_values keeps only each group's signature yards", {
  sa <- tibble::tibble(
    playerId = c("1", "1", "1", "3"),
    player = c("A", "A", "A", "C"),
    season = c(2019L, 2020L, 2020L, 2019L),
    season_index = c(1L, 2L, 2L, 1L),
    team = c("T", "T", "T", "U"),
    category = c("passing", "passing", "rushing", "rushing"),
    statType = c("YDS", "YDS", "ATT", "YDS"),
    value = c(200, 300, 5, 80)
  )
  pos <- tibble::tibble(
    playerId = c("1", "3"),
    pos = c("QB", "RB"),
    group = c("Quarterback", "Running back")
  )
  out <- signature_season_values(sa, pos)
  expect_equal(nrow(out), 3L)
  expect_equal(out$value, c(200, 300, 80))
  expect_equal(out$group, c("Quarterback", "Quarterback", "Running back"))
})

test_that("signature_game_values uses each group's game stat and banded opponents", {
  gp <- tibble::tibble(
    playerId = c("1", "1", "5"),
    gameId = c("g1", "g1", "g2"),
    season = c(2019L, 2019L, 2019L),
    week = c(1L, 1L, 2L),
    team = c("T", "T", "U"),
    opponent = c("O", "O", "P"),
    opponent_elo_band = c("1400 to 1599", "1400 to 1599", "Unrated"),
    stat = c("pass_yds", "rush_yds", "rec_yds"),
    value = c(250, 40, 60),
    baseline = c(200, 30, 50),
    band_n = c(10L, 10L, 4L),
    residual = c(50, 10, 10)
  )
  pos <- tibble::tibble(
    playerId = c("1", "5"),
    pos = c("QB", "WR"),
    group = c("Quarterback", "Receiver")
  )
  out <- signature_game_values(gp, pos)
  expect_equal(nrow(out), 2L)
  expect_equal(out$group, c("Quarterback", "Receiver"))
  expect_equal(levels(out$band)[1:2], c("Under 1400", "1400 to 1599"))
  expect_equal(as.character(out$band), c("1400 to 1599", "Unrated"))
})

test_that("median_arcs keeps only career seasons where every group has enough players", {
  values <- tibble::tibble(
    group = c(rep("A", 3), "A", rep("B", 3), rep("B", 3)),
    season_index = c(1L, 1L, 1L, 2L, 1L, 1L, 1L, 2L, 2L, 2L),
    value = c(100, 200, 300, 400, 50, 60, 70, 80, 90, 95)
  )
  out <- median_arcs(values, min_players = 2L)
  expect_equal(unique(out$season_index), 1L)
  a <- out[out$group == "A", ]
  expect_equal(a$med, 200)
  expect_equal(a$players, 3L)
})

test_that("band_gradient and band_drop compare the weakest and strongest rated bands", {
  games <- tibble::tibble(
    group = rep("A", 5),
    band = factor(
      c("Under 1400", "Under 1400", "1800 and up", "1800 and up", "Unrated"),
      c("Under 1400", "1400 to 1599", "1600 to 1799", "1800 and up", "Unrated")
    ),
    value = c(120, 80, 60, 60, 10)
  )
  grad <- band_gradient(games)
  expect_equal(grad$mean_yds[grad$band == "Under 1400"], 100)
  drop <- band_drop(grad)
  expect_equal(drop$drop, 40)
})

test_that("residual_spread scales the residual SD by the group's mean yards", {
  games <- tibble::tibble(
    group = c("A", "A"),
    residual = c(-1, 1),
    value = c(10, 10)
  )
  out <- residual_spread(games)
  expect_equal(out$games, 2L)
  expect_equal(out$sd, sqrt(2))
  expect_equal(out$rel_sd, sqrt(2) / 10)
})

test_that("stat_line_share counts rostered player-seasons with a line in any game", {
  usage <- tibble::tibble(
    playerId = c("1", "2", "3", "4"),
    season = c(2019L, 2019L, 2019L, 2018L),
    team = c("T", "T", "T", "T"),
    position_group = c(
      "Offensive line",
      "Offensive line",
      "Quarterback",
      "Quarterback"
    ),
    on_roster = TRUE,
    team_games = c(4L, 4L, 4L, 4L),
    games_appeared = c(2L, 0L, 4L, 4L),
    appearance_rate = c(0.5, 0, 1, 1)
  )
  out <- stat_line_share(usage, seasons = 2019:2025)
  ol <- out[out$position_group == "Offensive line", ]
  expect_equal(ol$player_seasons, 2L)
  expect_equal(ol$any_line, 0.5)
  expect_equal(ol$median_share_if_any, 0.5)
  expect_false(any(
    out$position_group == "Quarterback" & out$player_seasons == 2L
  ))
})

test_that("drafted_stat_line labels rostered seasons with the draft outcome", {
  usage <- tibble::tibble(
    playerId = c("1", "2", "3"),
    season = c(2020L, 2020L, 2020L),
    team = c("T", "T", "T"),
    position_group = c("Quarterback", "Receiver", "Receiver"),
    on_roster = TRUE,
    team_games = c(4L, 4L, 4L),
    games_appeared = c(4L, 1L, 2L),
    appearance_rate = c(1, 0.25, 0.5)
  )
  outcomes <- tibble::tibble(
    playerId = c("1", "2"),
    season = c(2020L, 2020L),
    draft_eligible = c(TRUE, TRUE),
    outcome_drafted_d = c(TRUE, FALSE)
  )
  out <- drafted_stat_line(usage, outcomes, seasons = 2019:2025)
  expect_equal(nrow(out), 2L)
  expect_equal(out$drafted, c(TRUE, FALSE))
})

test_that("early_stop_comparison sets each group's early stop against its runner-up", {
  statline <- tibble::tibble(
    position_group = c(rep("Quarterback", 6)),
    career_end = c(
      "early_stop",
      "early_stop",
      "early_stop",
      "drafted",
      "drafted",
      "signed_udfa"
    )
  )
  out <- early_stop_comparison(statline)
  early <- out[out$bar == "Stopped with eligibility left", ]
  runner <- out[out$bar == "Next most common ending", ]
  expect_equal(early$share, 0.5)
  expect_equal(runner$career_end, "drafted")
  expect_equal(runner$share, 2 / 6)
})

test_that("absence_summary shares are among the seasons that can be read", {
  absence <- tibble::tibble(
    position_group = rep("Quarterback", 4),
    observable = c(TRUE, TRUE, TRUE, FALSE),
    absence_shape = c("returned", "season_ending", "none", "not_observable")
  )
  out <- absence_summary(absence)
  expect_equal(out$seasons, 4L)
  expect_equal(out$readable_n, 3L)
  expect_equal(out$readable, 0.75)
  expect_equal(out$returned, 1 / 3)
  expect_equal(out$injury_shaped, 2 / 3)
})

test_that("final_endings reads each ending's final season", {
  statline <- tibble::tibble(
    playerId = c("1", "2", "3", "4"),
    last_season = c(2020L, 2020L, 2020L, 2020L),
    career_end = c("early_stop", "early_stop", "early_stop", "drafted")
  )
  absence <- tibble::tibble(
    playerId = c("1", "2", "4"),
    season = c(2020L, 2020L, 2020L),
    observable = c(TRUE, TRUE, FALSE),
    absence_shape = c("season_ending", "none", "not_observable")
  )
  out <- final_endings(
    statline,
    absence,
    window = 2016:2025,
    final_endings = c("early_stop", "drafted")
  )
  early <- out[out$career_end == "early_stop", ]
  expect_equal(early$careers, 3L)
  expect_equal(early$readable, 2 / 3)
  expect_equal(early$season_ending, 0.5)
})

test_that("redshirt_spine flags a season with one covered-game statistic and leaves thin coverage unresolved", {
  flags <- tibble::tibble(
    playerId = c("1", "1", "1"),
    season = c(2019L, 2020L, 2021L),
    team = c("T", "T", "T")
  )
  attempts <- tibble::tibble(playerId = "1", season = 2019L, attempts = 3)
  player_games <- tibble::tibble(
    playerId = c("1", "1"),
    season = c(2019L, 2020L),
    games_with_stat = c(1L, 3L)
  )
  covered <- tibble::tibble(
    season = c(2019L, 2020L, 2021L),
    team = "T",
    games_covered = c(12L, 12L, 2L)
  )
  out <- redshirt_spine(flags, attempts, player_games, covered)
  expect_equal(out$likely_rs, c(TRUE, FALSE, NA))
  expect_equal(
    out$flag_label,
    c("Redshirt-shaped", "Played", "Unresolvable (under 5 covered games)")
  )
  expect_equal(out$games_with_stat[3], 0L)
})

test_that("observability_by_position compares full-time and other seasons, in complete seasons only", {
  stat_rate <- tibble::tibble(
    pos = "QB",
    season = c(2019L, 2019L, 2019L, 2019L, 2026L),
    volume = c(10, 20, 30, 40, 40),
    rate = c(0.1, 0.2, 0.3, 0.4, 0.9)
  )
  out <- observability_by_position(stat_rate, last_season = 2025L)
  full <- out[out$full_time, ]
  other <- out[!out$full_time, ]
  expect_equal(full$rate, 0.4)
  expect_equal(full$n, 1L)
  expect_equal(other$rate, 0.2)
  expect_equal(other$n, 3L)
})

test_that("label_text_colour picks white on dark team colours and dark text on light", {
  expect_equal(
    label_text_colour(c("#000000", "#FFFFFF")),
    c("white", "#111827")
  )
})
