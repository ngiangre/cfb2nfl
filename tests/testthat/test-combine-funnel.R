# Combine invite-to-draft funnel (issue #64): invitees placed against the
# draft-eligible population of the outcomes table, joined on athlete id.

funnel_outcomes <- function() {
  tibble::tibble(
    playerId = c("a", "b", "c", "d", "e", "e", "f"),
    season = c(2019L, 2019L, 2019L, 2019L, 2018L, 2019L, 2025L),
    draft_year = season + 1L,
    draft_eligible = c(TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, TRUE),
    outcome_observed_d = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
    outcome_drafted_d = c(TRUE, FALSE, TRUE, FALSE, FALSE, TRUE, NA)
  )
}

funnel_combine <- function() {
  tibble::tibble(
    season = c(2020L, 2020L, 2020L, 2020L, 2020L, 2026L),
    player_name = c("A", "B", "D", "G", "Lineman", "F"),
    pos = c("QB", "WR", "OT", "CB", "OG", "RB"),
    athlete_id = c("a", "b", "d", "g", NA, "f"),
    link_method = c(
      "draft_slot",
      "name_school",
      "name_school",
      "name_school",
      "unmatched",
      "name_school"
    )
  )
}

test_that("combine_funnel_status places every invitee in one band", {
  out <- combine_funnel_status(funnel_combine(), funnel_outcomes())
  expect_equal(nrow(out), nrow(funnel_combine()))
  expect_equal(
    out$funnel_status,
    c(
      "eligible",
      "eligible",
      # d's season is not draft-eligible; g has no outcomes row at all
      "outside_population",
      "outside_population",
      "unmatched",
      # f's draft has not happened, so it is outside the observed population
      "outside_population"
    )
  )
})

test_that("build_combine_funnel keeps one row per observed eligible season", {
  out <- build_combine_funnel(funnel_combine(), funnel_outcomes())
  expected <- funnel_outcomes() |>
    dplyr::filter(draft_eligible, outcome_observed_d)
  expect_equal(nrow(out), nrow(expected))
  expect_named(out, c("playerId", "season", "draft_year", "invited", "drafted"))
  invited <- out$invited[order(out$playerId, out$draft_year)]
  # a and b invited in 2020; c never; e's 2019 and 2020 seasons not invited
  expect_equal(invited, c(TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_type(out$drafted, "logical")
})

test_that("build_combine_funnel matches invitees to the combine year only", {
  cmb <- funnel_combine()
  cmb$season[1] <- 2019L
  out <- build_combine_funnel(cmb, funnel_outcomes())
  expect_false(out$invited[out$playerId == "a"])
})
