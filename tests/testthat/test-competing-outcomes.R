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

test_that("ending_multinom with season terms reproduces the hazards and Aalen-Johansen", {
  skip_if_not_installed("nnet")
  skip_if_not_installed("survival")
  e <- endings_fixture()
  m <- ending_multinom(e)
  h <- ending_hazards(e, by = NULL)
  ci <- ending_incidence(e, by = NULL)
  at <- function(d, t, s, col) d[[col]][d$time == t & d$state == s]
  # Season 1: 5 at risk, 1 drafted, 1 ended, 3 play on (C censored after it).
  expect_equal(at(m, 1, "drafted", "chance"), 0.2, tolerance = 1e-3)
  expect_equal(at(m, 1, "playing", "chance"), 0.6, tolerance = 1e-3)
  expect_equal(at(m, 2, "drafted", "chance"), 0.5, tolerance = 1e-3)
  expect_equal(
    at(m, 2, "drafted", "chance"),
    h$hazard[h$time == 2 & h$ending == "drafted"],
    tolerance = 1e-3
  )
  # The chances compound into the Aalen-Johansen cumulative shares.
  expect_equal(
    at(m, 2, "drafted", "cumulative"),
    at(ci, 2, "drafted", "estimate"),
    tolerance = 1e-3
  )
  expect_equal(at(m, 2, "playing", "cumulative"), 0, tolerance = 1e-3)
  expect_equal(at(m, 1, "drafted", "n_risk"), 5L)
  # Each season's chances, and each season's cumulative shares, sum to one.
  expect_equal(as.vector(tapply(m$chance, m$time, sum)), c(1, 1))
  expect_equal(as.vector(tapply(m$cumulative, m$time, sum)), c(1, 1))
})

test_that("ending_multinom without season terms pools one chance per ending", {
  skip_if_not_installed("nnet")
  m <- ending_multinom(endings_fixture(), season_terms = FALSE)
  # 7 player-seasons: 2 drafted, 2 ended, 3 played on, the same each season.
  expect_equal(
    unique(round(m$chance[m$state == "drafted"], 3)),
    round(2 / 7, 3)
  )
  expect_equal(
    m$cumulative[m$time == 2 & m$state == "playing"],
    (3 / 7)^2,
    tolerance = 1e-3
  )
})

test_that("ending_multinom with a group term matches each group's ending totals", {
  skip_if_not_installed("nnet")
  e <- dplyr::bind_rows(
    endings_fixture(),
    dplyr::mutate(
      endings_fixture(),
      playerId = paste0(playerId, "2"),
      group = "Linebacker",
      ending = c(
        "censored",
        "exhausted_undrafted",
        "censored",
        "drafted",
        "exhausted_undrafted"
      )
    )
  )
  m <- ending_multinom(e, by = "group")
  expect_setequal(unique(m$group), c("Linebacker", "Receiver"))
  expect_equal(m$n_risk[m$group == "Linebacker" & m$time == 2][1], 2L)
  # A main effect's score equations: fitted drafted endings in a group,
  # summed over its seasons at risk, equal its observed drafted endings.
  fitted_drafted <- m |>
    dplyr::filter(state == "drafted") |>
    dplyr::summarise(n = sum(chance * n_risk), .by = "group")
  expect_equal(
    fitted_drafted$n[fitted_drafted$group == "Linebacker"],
    1,
    tolerance = 1e-3
  )
  expect_equal(
    fitted_drafted$n[fitted_drafted$group == "Receiver"],
    2,
    tolerance = 1e-3
  )
  sums <- m |> dplyr::summarise(s = sum(chance), .by = c("group", "time"))
  expect_equal(sums$s, rep(1, nrow(sums)), tolerance = 1e-8)
})
