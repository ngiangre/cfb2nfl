# Shared builders for the career-endings cards (feature F25).

# Five receivers, as in test-competing-outcomes.R, with E signing undrafted
# and two players without a matched recruiting record.
endings_cards_fixture <- function() {
  tibble::tibble(
    playerId = c("A", "B", "C", "D", "E"),
    player = c("A", "B", "C", "D", "E"),
    group = "Receiver",
    hs_year_imputed = c(FALSE, TRUE, FALSE, TRUE, FALSE),
    time = c(1L, 1L, 1L, 2L, 2L),
    ending = c(
      "drafted",
      "exhausted_undrafted",
      "censored",
      "drafted",
      "signed_udfa"
    ),
    round = c(1L, NA, NA, 3L, NA),
    missed_season = FALSE
  )
}

test_that("label_endings orders position groups and names the recruiting-record split", {
  out <- label_endings(endings_cards_fixture())
  expect_s3_class(out$group, "factor")
  expect_equal(
    levels(out$group),
    c(position_group_levels(), "Position not recorded")
  )
  expect_equal(
    out$recruited,
    c(
      "Matched recruiting record",
      "No matched recruiting record",
      "Matched recruiting record",
      "No matched recruiting record",
      "Matched recruiting record"
    )
  )
})

test_that("ending_palette colours the two NFL routes and greys the rest", {
  pal <- ending_palette()
  expect_equal(
    names(pal),
    c(
      "Drafted",
      "Signed undrafted",
      "Eligibility ended, undrafted",
      "Left the data",
      "Still playing"
    )
  )
  expect_true(all(grepl("^#[0-9A-F]{6}$", pal)))
})

test_that("route_incidence adds either NFL route as one ending with its own interval", {
  skip_if_not_installed("survival")
  out <- route_incidence(endings_cards_fixture(), by = "group")
  expect_setequal(unique(out$state), c("drafted", "signed_udfa", "nfl"))
  at2 <- function(s) out$estimate[out$time == 2 & out$state == s]
  expect_equal(at2("nfl"), at2("drafted") + at2("signed_udfa"))
  expect_true(all(c("lower", "upper") %in% names(out)))
})

test_that("thin_position_groups names the groups with too few players at risk", {
  ci <- tibble::tibble(
    group = c("Quarterback", "Quarterback", "Special teams", "Special teams"),
    time = c(3L, 3L, 3L, 3L),
    state = c("drafted", "playing", "drafted", "playing"),
    n_risk = c(120L, 120L, 12L, 12L)
  )
  expect_equal(
    thin_position_groups(ci, horizon = 3L, min_risk = 30),
    "Special teams"
  )
})

test_that("population_leaves puts every roster player on one leaf of the flow chart", {
  # P never eligible; Q ruled out (drafted before eligible); R eligible with
  # no position; S drafted in round 2; T still playing.
  outcomes <- tibble::tibble(
    playerId = c("P", "Q", "R", "S", "S", "T"),
    player = c("P", "Q", "R", "S", "S", "T"),
    season = c(2014L, 2015L, 2016L, 2017L, 2018L, 2026L),
    draft_eligible = c(FALSE, FALSE, TRUE, TRUE, TRUE, TRUE),
    eligible_season_index = c(NA, NA, 1L, 1L, 2L, 1L),
    hs_year_imputed = FALSE,
    status_end_of_season = c(
      "left_data",
      "drafted",
      "exhausted_undrafted",
      "continuing",
      "drafted",
      "censored"
    ),
    outcome_observed_d = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
    outcome_draft_round_d = c(NA, 1L, NA, NA, 2L, NA),
    outcome_nfl_entry_d = c(FALSE, TRUE, FALSE, FALSE, TRUE, FALSE),
    outcome_drafted_d = c(FALSE, TRUE, FALSE, FALSE, TRUE, FALSE)
  )
  roster_pos <- tibble::tibble(
    playerId = c("P", "Q", "R", "S", "S", "T"),
    season = c(2014L, 2015L, 2016L, 2017L, 2018L, 2026L),
    position = c("LB", "QB", "?", "RB", "RB", "WR")
  )
  out <- population_leaves(outcomes, roster_pos)
  expect_equal(nrow(out), 5L)
  at <- function(id, col) out[[col]][out$playerId == id]
  expect_equal(
    as.character(out$leaf[order(out$playerId)]),
    c(
      "Never draft-eligible",
      "Ruled out",
      "Position not recorded",
      "Drafted, round 2",
      "Still playing"
    )
  )
  expect_equal(at("P", "group"), factor("Linebacker", levels(out$group)))
  expect_equal(as.character(at("Q", "group")), "Quarterback")
  expect_equal(at("S", "final_season"), 2018L)
  expect_true(all(levels(out$leaf) %in% names(leaf_palette())))
})

test_that("leaf_palette shades the draft rounds of drafted green", {
  pal <- leaf_palette()
  rounds <- pal[grepl("^Drafted, round", names(pal))]
  expect_length(rounds, 7L)
  expect_equal(unname(rounds[["Drafted, round 4"]]), "#1B9E77")
  expect_equal(unname(pal[["Signed undrafted"]]), "#7570B3")
  expect_true(all(grepl("^#[0-9A-F]{6}$", pal)))
  # Round 1 is the darkest.
  lum <- colSums(grDevices::col2rgb(rounds))
  expect_equal(order(lum), seq_along(rounds))
})
