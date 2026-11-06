# career_end_status() classifies each career's ending (issue #51, part 1;
# decision 0039). One hand-checked fixture per category, plus the censoring
# and clock edges. The max roster season is 2026 and the last complete draft is
# 2025 in every test, so a career ending in 2025 is right-censored (its draft is
# not yet complete) and one ending in 2024 is not.

career_fixture <- function() {
  tibble::tribble(
    ~playerId  , ~first_season , ~last_season , ~seasons , ~transfers , ~gap_seasons ,
    # drafted (picks bridge), 2016-2019
    "drafted"  , 2016L         , 2019L        , 4L       , 0L         , 0L           ,
    # undrafted, matched to an NFL roster
    "udfa"     , 2017L         , 2019L        , 3L       , 0L         , 0L           ,
    # 2014-2018 is five clock seasons, no NFL entry
    "exhaust"  , 2014L         , 2018L        , 5L       , 0L         , 0L           ,
    # 2018-2019 on one school with eligibility left
    "early"    , 2018L         , 2019L        , 2L       , 0L         , 0L           ,
    # 2018-2019, two schools
    "transfer" , 2018L         , 2019L        , 2L       , 1L         , 0L           ,
    # still on the most recent roster season
    "active"   , 2024L         , 2026L        , 3L       , 0L         , 0L           ,
    # last season 2025: the 2026 draft is past last_complete_draft
    "censor25" , 2022L         , 2025L        , 4L       , 0L         , 0L           ,
    # last season 2024: the 2025 draft is complete, so this is an early stop
    "ended24"  , 2021L         , 2024L        , 4L       , 0L         , 0L           ,
    # no stat line, no pick: NFL status unresolved
    "nostat"   , 2019L         , 2019L        , 1L       , 0L         , 0L           ,
    # no stat line, but drafted in 2021 via the picks bridge
    "nostat_d" , 2019L         , 2019L        , 1L       , 0L         , 0L           ,
    # 2016-2020 with 2020 not counted: four clock seasons, eligibility left
    "covid"    , 2016L         , 2020L        , 5L       , 0L         , 0L           ,
    # first roster season is the data start (2010): clock start unobserved
    "leftcens" , 2010L         , 2011L        , 2L       , 0L         , 0L           ,
    # left-censored, but five seasons observed: exhausted regardless
    "leftex"   , 2010L         , 2015L        , 6L       , 0L         , 0L
  )
}

outcomes_fixture <- function() {
  tibble::tibble(
    playerId = c(
      "drafted",
      "udfa",
      "early",
      "transfer",
      "ended24",
      "exhaust",
      "covid",
      "leftcens",
      "leftex",
      "active",
      "censor25"
    ),
    season = 2019L,
    outcome_drafted_d = c(
      TRUE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE
    ),
    outcome_signed_udfa_d = c(
      FALSE,
      TRUE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE
    )
  )
}

picks_fixture <- function() {
  tibble::tibble(
    playerId = c("drafted", "nostat_d"),
    year = c(2020L, 2021L),
    round = c(3L, 6L),
    overall = c(90L, 200L)
  )
}

classify <- function(career = career_fixture()) {
  career_end_status(
    career,
    outcomes_fixture(),
    picks_fixture(),
    last_complete_draft = 2025L
  )
}

test_that("each category is assigned to its fixture career", {
  ce <- classify()
  got <- stats::setNames(ce$career_end, ce$playerId)
  expect_equal(
    got[["drafted"]],
    "drafted"
  )
  expect_equal(got[["udfa"]], "signed_udfa")
  expect_equal(got[["exhaust"]], "eligibility_exhausted")
  expect_equal(got[["early"]], "early_stop")
  expect_equal(got[["transfer"]], "transferred_then_stopped")
  expect_equal(got[["active"]], "right_censored")
  expect_equal(got[["censor25"]], "right_censored")
  expect_equal(got[["ended24"]], "early_stop")
  expect_equal(got[["nostat"]], "not_in_model_population")
  expect_equal(got[["nostat_d"]], "drafted")
  expect_equal(got[["covid"]], "early_stop")
  expect_equal(got[["leftcens"]], "eligibility_unknown")
  expect_equal(got[["leftex"]], "eligibility_exhausted")
})

test_that("categories are exhaustive, one per career, and in the known set", {
  career <- career_fixture()
  ce <- classify(career)
  expect_equal(nrow(ce), nrow(career))
  expect_false(anyDuplicated(ce$playerId) > 0L)
  expect_true(all(ce$career_end %in% names(career_end_levels)))
})

test_that("censored careers are never early stops", {
  ce <- classify()
  cens <- dplyr::filter(ce, .data$right_censored)
  expect_setequal(cens$playerId, c("active", "censor25"))
  expect_false(any(cens$early_stop_proxy))
})

test_that("the early-stop proxy is exactly the early_stop category", {
  ce <- classify()
  expect_setequal(
    ce$playerId[ce$early_stop_proxy],
    c("early", "ended24", "covid")
  )
  expect_equal(ce$early_stop_proxy, ce$career_end == "early_stop")
})

test_that("the COVID-19 season is not counted against eligibility", {
  ce <- classify()
  covid <- dplyr::filter(ce, .data$playerId == "covid")
  # 2016..2020 is five calendar seasons; 2020 is not counted.
  expect_equal(covid$clock_seasons_used, 4L)
  expect_equal(covid$eligibility_remaining, 1L)
  exhaust <- dplyr::filter(ce, .data$playerId == "exhaust")
  expect_equal(exhaust$clock_seasons_used, 5L)
  expect_equal(exhaust$eligibility_remaining, 0L)
})

test_that("a left-censored clock is unknown unless already exhausted", {
  ce <- classify()
  expect_false(
    dplyr::filter(ce, .data$playerId == "leftcens")$clock_start_observed
  )
  expect_true(dplyr::filter(ce, .data$playerId == "early")$clock_start_observed)
})

test_that("drafted and UDFA labels never both hold", {
  ce <- classify()
  expect_false(any(ce$drafted & ce$signed_udfa))
  expect_true(dplyr::filter(ce, .data$playerId == "drafted")$drafted)
  expect_true(dplyr::filter(ce, .data$playerId == "udfa")$signed_udfa)
})

test_that("the derived table passes its contract", {
  career <- career_fixture()
  ce <- classify(career)
  agent <- contract_career_end(ce, career, stop_on_fail = FALSE)
  expect_true(pointblank::all_passed(agent))
})

test_that("the contract fails on a dropped row and on a mislabelled proxy", {
  career <- career_fixture()
  ce <- classify(career)
  dropped <- ce[-1, ]
  expect_false(
    pointblank::all_passed(contract_career_end(
      dropped,
      career,
      stop_on_fail = FALSE
    ))
  )
  bad <- ce
  bad$early_stop_proxy[bad$career_end == "transferred_then_stopped"] <- TRUE
  expect_false(
    pointblank::all_passed(contract_career_end(
      bad,
      career,
      stop_on_fail = FALSE
    ))
  )
})
