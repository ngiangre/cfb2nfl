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
