# Shared builders for the draft-outcome cards (feature F25).

outcomes_fixture <- function() {
  tibble::tibble(
    playerId = c("a", "a", "b", "c", "d", "e"),
    season = c(2019L, 2020L, 2020L, 2020L, 2021L, 2022L),
    draft_eligible = c(TRUE, TRUE, TRUE, FALSE, TRUE, TRUE),
    outcome_observed_d = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
    outcome_drafted_d = c(FALSE, TRUE, NA, FALSE, FALSE, NA),
    outcome_signed_udfa_d = c(FALSE, FALSE, NA, FALSE, TRUE, NA),
    outcome_nfl_entry_d = c(FALSE, TRUE, NA, FALSE, TRUE, NA),
    outcome_draft_round_d = c(NA, 1L, NA, NA, NA, NA)
  )
}

test_that("eligible_risk_set keeps eligible seasons with a known outcome and fills missing flags", {
  risk <- eligible_risk_set(outcomes_fixture())
  expect_equal(nrow(risk), 4L)
  expect_false(any(is.na(risk$outcome_drafted_d)))
  expect_equal(sum(risk$outcome_nfl_entry_d), 2L)
})

test_that("outcome_ledger counts each outcome over the eligible seasons with an interval", {
  ledger <- outcome_ledger(eligible_risk_set(outcomes_fixture()))
  expect_equal(
    ledger$outcome,
    c(
      "Drafted, any round",
      "Signed as an undrafted free agent",
      "NFL entry (drafted or undrafted)"
    )
  )
  expect_equal(ledger$events, c(1L, 1L, 2L))
  expect_true(all(ledger$at_risk == 4L))
  expect_equal(ledger$share, c(0.25, 0.25, 0.5))
  expect_true(all(ledger$lo <= ledger$share & ledger$share <= ledger$hi))
})

test_that("plot_outcome_ledger draws one bar per outcome and highlights the draft", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("ggiraph")
  p <- plot_outcome_ledger(outcome_ledger(eligible_risk_set(outcomes_fixture())))
  expect_s3_class(p, "ggplot")
  built <- ggplot2::ggplot_build(p)
  expect_equal(nrow(built$data[[1]]), 3L)
  expect_equal(sort(unique(built$data[[1]]$fill)), sort(c("#1B9E77", "grey65")))
})

test_that("plot_outcome_ledger labels every axis tick with its true percent", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("ggiraph")
  # Shares like the real ones, where default breaks fall on 2.5 and 7.5.
  ledger <- tibble::tibble(
    outcome = c(
      "Drafted, any round",
      "Signed as an undrafted free agent",
      "NFL entry (drafted or undrafted)"
    ),
    events = c(30L, 41L, 71L),
    at_risk = 1000L,
    share = c(0.030, 0.041, 0.071),
    lo = c(0.021, 0.030, 0.056),
    hi = c(0.042, 0.055, 0.089)
  )
  p <- plot_outcome_ledger(ledger)
  built <- ggplot2::ggplot_build(p)
  breaks <- built$layout$panel_params[[1]]$x$breaks
  breaks <- breaks[!is.na(breaks)]
  expect_true(all(breaks == round(breaks)))
})

test_that("running_cast names the recurring players by athlete id", {
  cast <- running_cast()
  expect_equal(
    names(cast),
    c("Joe Burrow", "Cam Ward", "Jordan Travis", "Shane Buechele", "Kyle Allen")
  )
  expect_true(all(grepl("^[0-9]+$", cast)))
})

test_that("add_position_group joins each season's roster position without adding rows", {
  risk <- eligible_risk_set(outcomes_fixture())
  roster <- tibble::tibble(
    playerId = c("a", "a", "a", "b"),
    season = c(2019L, 2020L, 2020L, 2020L),
    position = c("QB", "QB", "QB", "OT")
  )
  out <- add_position_group(risk, roster)
  expect_equal(nrow(out), nrow(risk))
  expect_equal(
    out$group,
    c("Quarterback", "Quarterback", "Offensive line", "Position not recorded")
  )
})
