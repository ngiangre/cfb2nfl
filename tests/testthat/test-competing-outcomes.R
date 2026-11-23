# Competing career endings (feature F24): the reduction from person-period
# rows, the Aalen-Johansen shares against a hand computation, and the
# drafted-only survival curve that overstates them.

endings_fixture <- function() {
  # Five players, one group. At season 1: A drafted, B eligibility ended,
  # C still playing but censored (outcome unknown). At season 2: D drafted,
  # E eligibility ended.
  tibble::tibble(
    playerId = c("A", "B", "C", "D", "E"),
    player = c("A", "B", "C", "D", "E"),
    group = "Receiver",
    hs_year_imputed = FALSE,
    time = c(1L, 1L, 1L, 2L, 2L),
    ending = c(
      "drafted",
      "exhausted_undrafted",
      "censored",
      "drafted",
      "exhausted_undrafted"
    ),
    round = c(1L, NA, NA, 3L, NA),
    missed_season = FALSE
  )
}

test_that("ending_incidence matches a hand-computed Aalen-Johansen estimate", {
  skip_if_not_installed("survival")
  ci <- ending_incidence(endings_fixture())
  at <- function(t, s) ci$estimate[ci$time == t & ci$state == s]
  # Season 1: 5 at risk, 1 drafted, 1 ended -> 0.2 each, 0.6 still playing.
  expect_equal(at(1, "drafted"), 0.2)
  expect_equal(at(1, "exhausted_undrafted"), 0.2)
  expect_equal(at(1, "playing"), 0.6)
  # C is censored after season 1, so D and E are the risk set in season 2:
  # each ending adds 0.6 * 1/2.
  expect_equal(at(2, "drafted"), 0.5)
  expect_equal(at(2, "exhausted_undrafted"), 0.5)
  expect_equal(at(2, "playing"), 0)
  expect_equal(ci$n_risk[ci$time == 2 & ci$state == "drafted"], 2L)
  # Every season's shares sum to one, and time 0 starts everyone playing.
  sums <- tapply(ci$estimate, ci$time, sum)
  expect_equal(as.vector(sums), rep(1, length(sums)))
  expect_equal(at(0, "playing"), 1)
  expect_true(all(ci$lower <= ci$estimate + 1e-12))
  expect_true(all(ci$upper >= ci$estimate - 1e-12))
})

test_that("the drafted-only survival curve overstates the drafted share", {
  skip_if_not_installed("survival")
  naive <- naive_drafted(endings_fixture())
  # KM: season 1, 1 of 5 drafted -> S = 0.8; season 2, 1 of 2 -> S = 0.4.
  expect_equal(naive$estimate[naive$time == 2], 0.6)
  ci <- ending_incidence(endings_fixture())
  expect_gt(
    naive$estimate[naive$time == 2],
    ci$estimate[ci$time == 2 & ci$state == "drafted"]
  )
})

test_that("treating left_data as censoring removes it as a state", {
  skip_if_not_installed("survival")
  e <- endings_fixture()
  e$ending[2] <- "left_data"
  competing <- ending_incidence(e)
  censored <- ending_incidence(e, left_data = "censored")
  expect_true("left_data" %in% competing$state)
  expect_false("left_data" %in% censored$state)
  # Censoring B instead of ending his career leaves more players at risk of
  # being drafted later, so the drafted share can only rise.
  d2 <- function(x) x$estimate[x$time == 2 & x$state == "drafted"]
  expect_gte(d2(censored), d2(competing))
})

test_that("career_endings takes the final eligible row and censors the unknown", {
  outcomes <- tibble::tibble(
    playerId = c("V", "V", "V", "W", "W"),
    player = c("Vaughn", "Vaughn", "Vaughn", "Later", "Later"),
    season = c(2016L, 2018L, 2019L, 2024L, 2025L),
    draft_eligible = TRUE,
    eligible_season_index = c(1L, 2L, 3L, 1L, 2L),
    hs_year_imputed = FALSE,
    # Vaughn misses 2017 (a left_data row that is not his ending), then is
    # drafted; Later's 2025 outcome is not yet known.
    status_end_of_season = c(
      "left_data",
      "continuing",
      "drafted",
      "continuing",
      "censored"
    ),
    outcome_observed_d = c(TRUE, TRUE, TRUE, TRUE, FALSE),
    outcome_draft_round_d = c(NA, NA, 3L, NA, NA)
  )
  roster_pos <- tibble::tibble(
    playerId = c("V", "W"),
    season = c(2016L, 2024L),
    position = c("RB", "WR")
  )
  e <- career_endings(outcomes, roster_pos)
  v <- e[e$playerId == "V", ]
  expect_equal(v$ending, "drafted")
  expect_equal(v$time, 3L)
  expect_equal(v$round, 3L)
  expect_true(v$missed_season)
  expect_equal(v$group, "Running back")
  w <- e[e$playerId == "W", ]
  expect_equal(w$ending, "censored")
  expect_equal(w$time, 1L)
})

test_that("never_eligible_entrants finds entrants outside every risk set", {
  outcomes <- tibble::tibble(
    playerId = c("X", "Y"),
    player = c("Early", "Eligible"),
    season = c(2015L, 2016L),
    draft_eligible = c(FALSE, TRUE),
    outcome_nfl_entry_d = c(TRUE, TRUE),
    outcome_drafted_d = c(TRUE, FALSE)
  )
  roster_pos <- tibble::tibble(playerId = "X", season = 2015L, position = "QB")
  n <- never_eligible_entrants(outcomes, roster_pos)
  expect_equal(n$playerId, "X")
  expect_equal(n$route, "drafted")
  expect_equal(n$group, "Quarterback")
})

test_that("ending_hazards divides each season's endings by those still playing", {
  h <- ending_hazards(endings_fixture())
  at <- function(t, s) h[h$time == t & h$ending == s, ]
  expect_equal(at(1, "drafted")$at_risk, 5L)
  expect_equal(at(1, "drafted")$hazard, 0.2)
  expect_equal(at(2, "drafted")$at_risk, 2L)
  expect_equal(at(2, "drafted")$hazard, 0.5)
  expect_equal(at(2, "left_data")$hazard, 0)
  expect_true(all(h$lower <= h$hazard & h$hazard <= h$upper))
  expect_equal(at(2, "left_data")$lower, 0)
})

test_that("explorer_player_url links stat groups and skips the offensive line", {
  url <- explorer_player_url(c("1", "2"), c("Running back", "Offensive line"))
  expect_equal(url[1], "explorer.html#tab=players&pos=RB&player=1")
  expect_true(is.na(url[2]))
})
