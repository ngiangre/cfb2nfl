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
