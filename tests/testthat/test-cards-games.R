# Game-flow figure cards (feature F25): the shared builders behind the
# Georgia vs Missouri cards. Each test uses a small synthetic play log so the
# rules are checked without the data bundle.

synthetic_season <- function(n = 400) {
  set.seed(1)
  tibble::tibble(
    gameId = 1L,
    driveId = paste0("d", rep(1:40, each = 10)[seq_len(n)]),
    driveNumber = rep(1:40, each = 10)[seq_len(n)],
    playNumber = rep(1:10, 40)[seq_len(n)],
    period = sample(1:4, n, replace = TRUE),
    offense = sample(c("Alpha", "Beta"), n, replace = TRUE),
    defense = NA_character_,
    home = "Alpha",
    away = "Beta",
    offenseScore = sample(0:21, n, replace = TRUE),
    defenseScore = sample(0:21, n, replace = TRUE),
    yardsToGoal = sample(1:99, n, replace = TRUE),
    down = sample(1:4, n, replace = TRUE),
    distance = sample(1:15, n, replace = TRUE),
    yardsGained = sample(-3:20, n, replace = TRUE),
    playType = "Rush",
    playText = "rush",
    ppa = stats::rnorm(n, sd = 0.5)
  ) |>
    dplyr::mutate(defense = dplyr::if_else(offense == "Alpha", "Beta", "Alpha"))
}

test_that("scrimmage plays drop kicks, penalties and period markers, in game order", {
  plays <- tibble::tibble(
    id = c("c", "b", "a", "d"),
    driveNumber = c(2, 1, 1, 1),
    playNumber = c(1, 2, 1, 3),
    playType = c("Rush", "Pass Reception", "Kickoff", "Penalty")
  )
  scr <- game_scrimmage(plays)
  expect_equal(scr$id, c("b", "c"))
  expect_equal(scr$seq, 1:2)
})

test_that("play bands split explosive, ordinary and negative plays", {
  epa <- tibble::tibble(
    period = c(1L, 1L, 2L, 2L),
    clock_minutes = c(10L, 9L, 8L, 7L),
    clock_seconds = c(0L, 0L, 0L, 0L),
    ppa = c(2, 0.5, -1, NA)
  )
  bands <- game_bands(epa, threshold = 1.5)
  expect_equal(nrow(bands), 3L)
  expect_equal(
    bands$band,
    c(
      "Explosive play (EPA 1.5+)",
      "Ordinary play (EPA 0 to 1.5)",
      "Negative play (EPA below 0)"
    )
  )
  expect_equal(bands$quarter, c("Q1", "Q1", "Q2"))
})

test_that("running EPA accumulates within each offense in game order", {
  epa <- tibble::tibble(
    seq = 1:4,
    offense = c("A", "B", "A", "B"),
    period = 1L,
    clock_minutes = 5L,
    clock_seconds = 0L,
    ppa = c(1, -2, 3, -1)
  )
  run <- game_running(epa)
  expect_equal(run$cum_ppa[run$offense == "A"], c(1, 4))
  expect_equal(run$cum_ppa[run$offense == "B"], c(-2, -3))
  expect_equal(run$play_n[run$offense == "A"], 1:2)
})

test_that("expected points follow field position, not just down and distance", {
  season <- synthetic_season()
  fit <- game_ep_fit(season)
  near <- game_ep_at(fit, rep(5, 3), c(1, 2, 3), c(10, 5, 2))
  far <- game_ep_at(fit, rep(90, 3), c(1, 2, 3), c(10, 5, 2))
  expect_length(near, 3L)
  expect_true(all(near > far))
})

test_that("season involvement names log and text players across every game", {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbWriteTable(
    con,
    "plays",
    data.frame(
      id = c("p1", "p2", "p3", "p4"),
      gameId = c(1L, 1L, 2L, 2L),
      season = 2026L,
      offense = c("Alpha", "Alpha", "Gamma", "Gamma"),
      ppa = c(1, -0.5, 2, NA),
      playType = c("Rush", "Rush", "Pass Reception", "Rush"),
      playText = c(
        "#5 A.Back run for 4 yds (#9 B.Tackler)",
        "#5 A.Back run for no gain",
        "#1 C.Passer pass complete to #8 C.Catcher",
        "#5 A.Back run"
      ),
      period = 1L,
      yardsGained = c(4L, 0L, 12L, 2L)
    )
  )
  DBI::dbWriteTable(
    con,
    "play_stats",
    data.frame(
      playId = c("p1", "p2", "p3", "p3"),
      season = 2026L,
      athleteId = c("10", "10", "30", "31"),
      athleteName = c("Al Back", "Al Back", "Cy Passer", "Cal Catcher"),
      team = c("Alpha", "Alpha", "Gamma", "Gamma"),
      statType = c("Rush", "Rush", "Completion", "Reception")
    )
  )
  DBI::dbWriteTable(
    con,
    "roster",
    data.frame(
      playerId = c("10", "20", "30", "31"),
      season = 2026L,
      team = c("Alpha", "Beta", "Gamma", "Gamma"),
      jersey = c(5L, 9L, 1L, 8L),
      position = c("RB", "LB", "QB", "WR")
    )
  )
  DBI::dbWriteTable(
    con,
    "player_stats",
    data.frame(
      playerId = c("10", "20", "30", "31"),
      season = 2026L,
      team = c("Alpha", "Beta", "Gamma", "Gamma"),
      player = c("Al Back", "Bo Tackler", "Cy Passer", "Cal Catcher")
    )
  )
  DBI::dbWriteTable(
    con,
    "games",
    data.frame(
      id = c(1L, 2L),
      season = 2026L,
      homeTeam = c("Alpha", "Gamma"),
      awayTeam = c("Beta", "Delta"),
      homeConference = c("SEC", "Big Sky"),
      awayConference = c("Sun Belt", "NESCAC")
    )
  )
  DBI::dbWriteTable(
    con,
    "conference_tiers",
    data.frame(
      season = 2026L,
      conference = c("SEC", "Sun Belt", "Big Sky"),
      tier = 3:1,
      tier_label = c("Power", "Group of 5", "FCS and below")
    )
  )
  out <- season_involvement(con, 2026)
  inv <- out$involvement
  # p4 has no PPA; the tackler comes from the play text alone.
  expect_setequal(unique(inv$id), c("p1", "p2", "p3"))
  tackle <- inv[inv$id == "p1" & inv$playerId == "20", ]
  expect_equal(tackle$source, "Play text")
  expect_equal(tackle$epa_side, -1)
  expect_equal(tackle$group, "Linebacker")
  expect_equal(inv$label[inv$playerId == "30"], "Cy Passer (Gamma)")
  expect_equal(out$unresolved, 0L)
  # The tier is the player's own conference in that game.
  expect_equal(tackle$tier_label, "Group of 5")
  expect_equal(unique(inv$tier_label[inv$team == "Gamma"]), "FCS and below")
})

test_that("top group players rank regulars only, highest EPA per involvement first", {
  inv <- tibble::tibble(
    playerId = c(rep("a", 10), rep("b", 10), "c", rep("d", 10)),
    player = playerId,
    team = "T",
    label = playerId,
    group = factor(
      c(rep("Receiver", 21), rep("Linebacker", 10)),
      harmonized_position_levels()
    ),
    epa_side = c(rep(0.5, 10), rep(1, 10), 5, rep(0.2, 10)),
    typical = 0
  )
  top <- top_group_players(inv, n = 1L, regular = 0.5)
  # c's one big play does not make it a regular.
  expect_equal(top$playerId, c("b", "d"))
  expect_equal(levels(top$group)[1], "Quarterback")
  expect_equal(top$min_inv, c(10, 10))
  expect_equal(top$rank, c(1L, 1L))
})

test_that("top group players carry Tukey whiskers that stop at the last play in range", {
  inv <- tibble::tibble(
    playerId = "a",
    player = "a",
    team = "T",
    label = "a",
    group = "Receiver",
    epa_side = c(1:9, 100),
    typical = 0
  )
  top <- top_group_players(inv, regular = 0)
  expect_equal(c(top$q1, top$q3), c(3.25, 7.75))
  expect_equal(c(top$lower, top$upper), c(1, 9))
})

test_that("top group players split by tier take the cut-off, typical play and rank within each tier", {
  inv <- tibble::tibble(
    playerId = c(rep("a", 4), rep("b", 2), rep("c", 4), rep("d", 4)),
    player = playerId,
    team = "T",
    label = playerId,
    group = "Receiver",
    tier_label = c(rep("Power", 6), rep("FCS and below", 8)),
    epa_side = c(rep(1, 4), rep(3, 2), rep(2, 4), rep(0, 4))
  )
  top <- top_group_players(inv, regular = 0.5, by = "tier_label")
  # b's two plays fall short of the Power cut-off but count in its typical play.
  expect_equal(top$playerId, c("c", "d", "a"))
  expect_equal(top$rank, c(1L, 2L, 1L))
  expect_equal(top$typical, c(1, 1, 5 / 3))
  expect_equal(top$min_inv, c(4, 4, 3))
})
