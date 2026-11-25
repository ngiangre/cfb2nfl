# drop_pre_enrollment() removes roster seasons CFBD lists before a player's
# name-matched recruiting class could have enrolled (issue #114).

roster_fx <- function() {
  tibble::tibble(
    playerId = c("1", "1", "1", "2", "2", "3", "3", "4"),
    season = c(2014L, 2015L, 2016L, 2019L, 2020L, 2013L, 2015L, 2018L),
    first_name = c(
      "Joe",
      "Joe",
      "Joe",
      "Cam",
      "Cam",
      "Ke'Shawn",
      "Ke'Shawn",
      "Ann"
    ),
    last_name = c(
      "Prep",
      "Prep",
      "Prep",
      "Ward",
      "Ward",
      "Vaughn",
      "Vaughn",
      "Ex"
    ),
    team = "Ohio State"
  )
}

recruiting_fx <- function() {
  tibble::tibble(
    # 1: class 2015, a 2014 roster row comes before enrollment.
    # 2: the id belongs to a different recruit, so the class is untrusted.
    # 3: no recruiting row (an estimated clock): nothing is dropped.
    playerId = c("1", "2"),
    recruit_name = c("Joe Prep", "Xavier Ward"),
    hs_class = c(2015L, 2021L)
  )
}

test_that("only seasons before a name-matched recruiting class are dropped", {
  out <- drop_pre_enrollment(roster_fx(), recruiting_fx())
  expect_equal(nrow(out), nrow(roster_fx()) - 1L)
  expect_false(any(out$playerId == "1" & out$season == 2014L))
  # A class on someone else's recruiting record and an unrecruited player
  # keep every season.
  expect_equal(out$season[out$playerId == "2"], c(2019L, 2020L))
  expect_equal(out$season[out$playerId == "3"], c(2013L, 2015L))
  expect_named(out, names(roster_fx()))
})

test_that("pre_enrollment_seasons() lists the dropped seasons", {
  flagged <- pre_enrollment_seasons(roster_fx(), recruiting_fx())
  expect_equal(flagged$playerId, "1")
  expect_equal(flagged$season, 2014L)
  expect_equal(flagged$hs_class, 2015L)
})

test_that("a roster with no recruiting match is returned unchanged", {
  out <- drop_pre_enrollment(roster_fx(), recruiting_fx()[0, ])
  expect_equal(out, roster_fx())
})

test_that("recycled ids are not flagged, so their span still excludes them", {
  # Id 1's 2014 season belongs to an earlier person on the same id (decision
  # 0022), not to a copy of the later record.
  flagged <- pre_enrollment_seasons(roster_fx(), recruiting_fx(), reused = "1")
  expect_equal(nrow(flagged), 0L)
  out <- drop_pre_enrollment(roster_fx(), recruiting_fx(), reused = "1")
  expect_equal(out, roster_fx())
})

test_that("a stat line before the class means the class is wrong, not the roster", {
  stats <- tibble::tibble(playerId = "1", season = 2014L)
  flagged <- pre_enrollment_seasons(roster_fx(), recruiting_fx(), stats)
  expect_equal(nrow(flagged), 0L)
  # A stat line only from the class on leaves the early season flagged.
  stats <- tibble::tibble(playerId = "1", season = 2015L)
  flagged <- pre_enrollment_seasons(roster_fx(), recruiting_fx(), stats)
  expect_equal(flagged$season, 2014L)
})
