# link_coaches_picks() + contract_coaches_picks() fixtures

co <- data.frame(
  school = c("Alpha", "Alpha", "Alpha", "Beta", "Beta", "Gamma"),
  season = c(2015L, 2016L, 2017L, 2016L, 2017L, 2016L),
  coach_id = c(1L, 1L, 2L, 3L, 3L, 4L),
  coach_name = c("Ann", "Ann", "Bo", "Cy", "Cy", "Dee")
)
ro <- data.frame(
  playerId = c("p1", "p1", "p2", "p2", "p3"),
  season = c(2015L, 2016L, 2016L, 2017L, 2016L),
  team = c("Alpha", "Beta", "Alpha", "Beta", "Alpha")
)
pk <- data.frame(
  playerId = c("p1", "p2", "p3", "p4"),
  year = c(2017L, 2018L, 2018L, 2018L),
  overall = c(10L, 20L, 30L, 40L),
  position = c("QB", "DE", "WR", "OT"),
  name = c("A", "B", "C", "D")
)

test_that("link_coaches_picks drops picks without an id and pre-draft seasons only", {
  # p4 has no roster seasons at all -> no link
  out <- link_coaches_picks(pk, ro, co, rule = "any")
  expect_false("p4" %in% out$name)
  expect_true(all(out$season < out$year))
  # p1's 2017 draft has no 2017 roster season attached
  expect_true(!any(out$name == "A" & out$season == 2017))
})

test_that("'last' credits only the final pre-draft season; 'any' credits all", {
  last <- link_coaches_picks(pk, ro, co, rule = "last")
  any_ <- link_coaches_picks(pk, ro, co, rule = "any")
  # p1: seasons 2015 (Alpha/Ann), 2016 (Beta/Cy). last -> Cy only; any -> both.
  p1_last <- last[last$name == "A", ]
  expect_setequal(p1_last$coach_name, "Cy")
  p1_any <- any_[any_$name == "A", ]
  expect_setequal(p1_any$coach_name, c("Ann", "Cy"))
  # p2: 2016 Alpha (Ann), 2017 Beta (Cy)
  expect_setequal(last[last$name == "B", ]$coach_name, "Cy")
  expect_setequal(any_[any_$name == "B", ]$coach_name, c("Ann", "Cy"))
})

test_that("multi-coach seasons credit every coach", {
  co_dup <- rbind(
    co,
    data.frame(
      school = "Beta",
      season = 2017L,
      coach_id = 9L,
      coach_name = "Zed"
    )
  )
  out <- link_coaches_picks(pk, ro, co_dup, rule = "last")
  expect_setequal(out[out$name == "B", ]$coach_name, c("Cy", "Zed"))
})

test_that("result is one row per (year, overall, coach_id)", {
  out <- link_coaches_picks(pk, ro, co, rule = "any")
  expect_equal(nrow(out), nrow(dplyr::distinct(out, year, overall, coach_id)))
})

test_that("reused ids are excluded when supplied", {
  out <- link_coaches_picks(pk, ro, co, rule = "any", reused = c("p1"))
  expect_false("A" %in% out$name)
  expect_true("B" %in% out$name)
})

test_that("draft_year_min gates the pick window", {
  out <- link_coaches_picks(pk, ro, co, rule = "any", draft_year_min = 2018L)
  expect_false("A" %in% out$name)
})

test_that("contract passes on well-formed output and fails on corruption", {
  out <- link_coaches_picks(pk, ro, co, rule = "last")
  expect_error(
    contract_coaches_picks(
      out,
      pk,
      ro,
      co,
      rule = "last",
      min_coverage = 0.5
    ),
    NA
  )
  out_any <- link_coaches_picks(pk, ro, co, rule = "any")
  expect_error(
    contract_coaches_picks(
      out_any,
      pk,
      ro,
      co,
      rule = "any",
      min_coverage = 0.5
    ),
    NA
  )
  # corrupt: a linked season that isn't the pick's max season (last rule)
  bad <- out
  bad$season[bad$name == "B"] <- 2016L
  expect_error(contract_coaches_picks(
    bad,
    pk,
    ro,
    co,
    rule = "last",
    min_coverage = 0.5
  ))
  # corrupt: coach id not in the coaches table
  bad2 <- out_any
  bad2$coach_id[1] <- 999L
  expect_error(contract_coaches_picks(
    bad2,
    pk,
    ro,
    co,
    rule = "any",
    min_coverage = 0.5
  ))
})
