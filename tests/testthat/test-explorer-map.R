explorer_map_teams_fixture <- function() {
  tibble::tibble(
    team_id = c(333L, 2L, 245L, 87L, 2000L),
    team = c(
      "Alabama",
      "Auburn",
      "Texas A&M",
      "Notre Dame",
      "Abilene Christian"
    ),
    venue = c(
      "Bryant-Denny Stadium",
      "Jordan-Hare Stadium",
      "Kyle Field",
      "Notre Dame Stadium",
      NA
    ),
    city = c("Tuscaloosa", "Auburn", "College Station", "South Bend", NA),
    state = c("AL", "AL", "TX", "IN", NA),
    latitude = c(33.2083, 32.6024, 30.6101, 41.6984, NA),
    longitude = c(-87.5504, -85.4890, -96.3403, -86.2339, NA)
  )
}

explorer_map_team_season_fixture <- function() {
  tibble::tibble(
    team_id = c(333L, 2L, 333L, 2L, 245L, 87L, 2000L),
    season = c(2011L, 2011L, 2012L, 2012L, 2012L, 2012L, 2012L),
    conference = c(
      "SEC",
      "SEC",
      "SEC",
      "SEC",
      "SEC",
      "FBS Independents",
      "WAC"
    ),
    classification = c("fbs", "fbs", "fbs", "fbs", "fbs", "fbs", "fcs")
  )
}

test_that("great_circle_miles matches a known distance and is zero to itself", {
  # New York City to Los Angeles is about 2,445 miles.
  expect_equal(
    great_circle_miles(40.7128, -74.0060, 34.0522, -118.2437),
    2445,
    tolerance = 0.005
  )
  expect_equal(great_circle_miles(33.2, -87.5, 33.2, -87.5), 0)
})

test_that("build_explorer_map keeps located teams and measures conference spread", {
  map <- build_explorer_map(
    explorer_map_teams_fixture(),
    explorer_map_team_season_fixture()
  )
  # Abilene Christian has no home venue, so it has no map row.
  expect_setequal(map$teams$team_id, c(333L, 2L, 245L, 87L))
  expect_named(
    map$teams,
    c("team_id", "latitude", "longitude", "city", "state", "venue")
  )
  spread <- map$spread
  # Independents are not a conference; a WAC with no located member has no spread.
  expect_false(any(grepl("Independent", spread$conference)))
  sec11 <- spread[spread$conference == "SEC" & spread$season == 2011L, ]
  sec12 <- spread[spread$conference == "SEC" & spread$season == 2012L, ]
  expect_equal(sec11$members, 2L)
  expect_equal(sec11$mapped, 2L)
  ab <- great_circle_miles(33.2083, -87.5504, 32.6024, -85.4890)
  expect_equal(sec11$spread_miles, round(ab))
  # Adding Texas A&M (far west of the Alabama schools) widens the SEC.
  expect_equal(sec12$members, 3L)
  expect_gt(sec12$spread_miles, sec11$spread_miles)
  wac <- spread[spread$conference == "WAC", ]
  expect_equal(c(wac$members, wac$mapped), c(1L, 0L))
  expect_true(is.na(wac$spread_miles))
  expect_equal(wac$classification, "fcs")
})

test_that("write_explorer_map writes columns and the contract passes", {
  dir <- withr::local_tempdir()
  ts <- explorer_map_team_season_fixture()
  map <- build_explorer_map(explorer_map_teams_fixture(), ts)
  path <- write_explorer_map(map, dir)
  back <- jsonlite::read_json(path)
  expect_equal(length(back$teams$team_id), 4L)
  expect_equal(length(back$spread$season), nrow(map$spread))
  expect_true(pointblank::all_passed(contract_explorer_map(
    map,
    ts,
    path,
    stop_on_fail = FALSE
  )))
  # An FBS team-season with no coordinates breaks the map.
  lost <- map
  lost$teams <- lost$teams[lost$teams$team_id != 245L, ]
  expect_false(pointblank::all_passed(contract_explorer_map(
    lost,
    ts,
    path,
    stop_on_fail = FALSE
  )))
  expect_false(pointblank::all_passed(contract_explorer_map(
    map,
    ts,
    path,
    max_gzip_bytes = 10L,
    stop_on_fail = FALSE
  )))
})
