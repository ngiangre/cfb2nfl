test_that("conference_tier_levels is an ordered 3-tier scale", {
  lv <- conference_tier_levels()
  expect_equal(unname(lv), c(1L, 2L, 3L))
  expect_equal(names(lv), c("FCS and below", "Group of 5", "Power"))
})

test_that("contract_conference_tiers passes a well-formed lookup and its coverage", {
  skip_if_not_installed("pointblank")
  tiers <- tibble::tibble(
    season = c(2015L, 2015L),
    conference = c("SEC", "Sun Belt"),
    tier = c(3L, 2L),
    tier_label = c("Power", "Group of 5")
  )
  stats <- tibble::tibble(season = 2015L, conference = c("SEC", "Sun Belt"))
  agents <- contract_conference_tiers(tiers, stats, stop_on_fail = FALSE)
  expect_true(pointblank::all_passed(agents$lookup))
  expect_true(pointblank::all_passed(agents$coverage))
})

test_that("contract_teams passes when every player_season team resolves", {
  skip_if_not_installed("pointblank")
  teams <- tibble::tibble(
    team = c("Alabama", "Troy"),
    logo_light = c("a.png", NA_character_),
    logo_dark = c("a-dark.png", NA_character_),
    conference = c("SEC", "Sun Belt")
  )
  ps <- tibble::tibble(team = c("Alabama", "Troy"))
  agents <- contract_teams(teams, ps, stop_on_fail = FALSE)
  expect_true(pointblank::all_passed(agents$dim))
  # A missing logo (Troy) is allowed; only coverage (row presence) is enforced.
  expect_true(pointblank::all_passed(agents$coverage))
})

test_that("contract_teams flags a team with no dimension row", {
  skip_if_not_installed("pointblank")
  teams <- tibble::tibble(
    team = "Alabama",
    logo_light = "a.png",
    logo_dark = "a-dark.png",
    conference = "SEC"
  )
  ps <- tibble::tibble(team = c("Alabama", "Nonexistent State"))
  agents <- contract_teams(teams, ps, stop_on_fail = FALSE)
  expect_false(pointblank::all_passed(agents$coverage))
})

test_that("contract_drafted passes a clean 1:1 draft-outcome join", {
  skip_if_not_installed("pointblank")
  ps <- tibble::tibble(playerId = c("1", "2"), season = c(2021L, 2021L))
  ps_draft <- link_drafted(
    ps,
    tibble::tibble(playerId = "1", year = 2022L, round = 3L, overall = 90L)
  )
  agent <- contract_drafted(ps_draft, ps, stop_on_fail = FALSE)
  expect_true(pointblank::all_passed(agent))
})

test_that("contract_drafted flags a fanned-out draft-outcome join", {
  skip_if_not_installed("pointblank")
  ps <- tibble::tibble(playerId = "1", season = 2021L)
  # Simulate the pre-fix fan-out: two outcome rows for one player-season.
  fanned <- tibble::tibble(
    playerId = c("1", "1"),
    season = c(2021L, 2021L),
    drafted = c(TRUE, TRUE),
    draft_year = c(2018L, 2022L),
    draft_round = c(1L, 3L),
    draft_overall = c(5L, 90L)
  )
  agent <- contract_drafted(fanned, ps, stop_on_fail = FALSE)
  expect_false(pointblank::all_passed(agent))
})

test_that("contract_player_trajectory passes a complete spine", {
  skip_if_not_installed("pointblank")
  spine <- tibble::tibble(
    who = c("A", "A", "B"),
    cfb_athlete_id = c("1", "1", "2"),
    season = c(2015L, 2018L, 2016L),
    team = c("Texas", "KC", "Texas A&M"),
    stage = c("College", "NFL", "College"),
    drafted = c(TRUE, TRUE, FALSE)
  )
  agent <- contract_player_trajectory(spine, stop_on_fail = FALSE)
  expect_true(pointblank::all_passed(agent))
})

test_that("contract_player_trajectory flags a null who/team/stage", {
  skip_if_not_installed("pointblank")
  spine <- tibble::tibble(
    who = c("A", NA_character_),
    cfb_athlete_id = c("1", "2"),
    season = c(2015L, 2018L),
    team = c("Texas", "KC"),
    stage = c("College", "NFL"),
    drafted = c(TRUE, FALSE)
  )
  agent <- contract_player_trajectory(spine, stop_on_fail = FALSE)
  expect_false(pointblank::all_passed(agent))
})

test_that("contract_conference_tiers flags an unmapped conference", {
  skip_if_not_installed("pointblank")
  tiers <- tibble::tibble(
    season = 2015L,
    conference = "SEC",
    tier = 3L,
    tier_label = "Power"
  )
  stats <- tibble::tibble(season = 2015L, conference = c("SEC", "MAC"))
  agents <- contract_conference_tiers(tiers, stats, stop_on_fail = FALSE)
  expect_false(pointblank::all_passed(agents$coverage))
})

test_that("contract_career_summary passes a valid summary and flags bounds", {
  skip_if_not_installed("pointblank")
  good <- tibble::tibble(
    playerId = c("1", "2"),
    seasons = c(4L, 1L),
    first_season = c(2018L, 2022L),
    last_season = c(2021L, 2022L),
    teams = c(2L, 1L),
    gap_seasons = c(0L, 0L),
    transfers = c(1L, 0L)
  )
  expect_true(pointblank::all_passed(
    contract_career_summary(good, stop_on_fail = FALSE)
  ))
  bad <- good |> dplyr::mutate(seasons = c(9L, 1L), gap_seasons = c(-1L, 0L))
  expect_false(pointblank::all_passed(
    contract_career_summary(bad, stop_on_fail = FALSE)
  ))
})

test_that("contract_redshirt passes valid flags and catches violations", {
  skip_if_not_installed("pointblank")
  good <- tibble::tibble(
    playerId = c("1", "1"),
    has_stats = c(FALSE, TRUE),
    redshirt_season = c(TRUE, FALSE),
    redshirt_career = c(TRUE, TRUE),
    fifth_year_career = c(FALSE, FALSE)
  )
  expect_true(pointblank::all_passed(
    contract_redshirt(good, stop_on_fail = FALSE)
  ))
  bad <- good |> dplyr::mutate(redshirt_season = c(TRUE, TRUE))
  expect_false(pointblank::all_passed(
    contract_redshirt(bad, stop_on_fail = FALSE)
  ))
})
