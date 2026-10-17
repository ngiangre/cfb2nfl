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

test_that("assert_contracts_pass stops listing failures and passes clean results", {
  expect_true(assert_contracts_pass(list(picks = TRUE, roster = NA)))
  expect_error(
    assert_contracts_pass(list(picks = TRUE, roster = FALSE, tiers = NA)),
    "roster"
  )
  expect_error(
    assert_contracts_pass(list(roster = FALSE, career = FALSE)),
    "2 data contracts failed"
  )
})

test_that("contract_player_season asserts grain uniqueness at (playerId, season, team)", {
  skip_if_not_installed("pointblank")
  good <- tibble::tibble(
    playerId = c("1", "1", "2"),
    season = c(2013L, 2013L, 2013L),
    team = c("IU", "Miami", "IU")
  )
  expect_true(pointblank::all_passed(
    contract_player_season(good, stop_on_fail = FALSE)
  ))
  # A true duplicate at the grain fails.
  bad <- good |> dplyr::add_row(playerId = "1", season = 2013L, team = "IU")
  expect_false(pointblank::all_passed(
    contract_player_season(bad, stop_on_fail = FALSE)
  ))
  # Out-of-window season fails.
  bad_year <- good |> dplyr::mutate(season = 2009L)
  expect_false(pointblank::all_passed(
    contract_player_season(bad_year, stop_on_fail = FALSE)
  ))
})

test_that("contract_picks keys on draft slot; id reuse is tolerated", {
  skip_if_not_installed("pointblank")
  make_picks <- function() {
    tibble::tibble(
      collegeAthleteId = c("1", "1", "2", NA_character_),
      year = c(1978L, 2009L, 2015L, 2015L),
      round = c(1L, 1L, 3L, 3L),
      overall = c(12L, 26L, 90L, 91L),
      pick = c(1L, 1L, 2L, 3L),
      nflAthleteId = NA_character_,
      collegeId = 1L,
      collegeConference = "B1G",
      nflTeamId = 1L,
      nflTeam = "X",
      name = c("a", "a", "b", "c"),
      preDraftPositionRanking = NA_integer_,
      preDraftGrade = NA_real_,
      hometownInfo_city = NA_character_,
      hometownInfo_country = "USA",
      hometownInfo_latitude = NA_real_,
      hometownInfo_longitude = NA_real_,
      hometownInfo_countyFips = NA_character_
    )
  }
  expect_true(pointblank::all_passed(
    contract_picks(make_picks(), stop_on_fail = FALSE)
  ))
  # Even an id repeated within one draft year (real case: two Derrick
  # Johnsons, Texas, 2005 — rounds 1 and 6) passes when the slot is unique.
  same_year <- make_picks() |>
    dplyr::mutate(
      year = c(2005L, 2005L, 2015L, 2015L),
      round = c(1L, 6L, 3L, 3L)
    )
  expect_true(pointblank::all_passed(
    contract_picks(same_year, stop_on_fail = FALSE)
  ))
  # A duplicated slot fails.
  bad_slot <- make_picks() |>
    dplyr::mutate(year = 2015L, round = 3L, pick = 2L)
  expect_false(pointblank::all_passed(
    contract_picks(bad_slot, stop_on_fail = FALSE)
  ))
})

test_that("contract_coach_link pins the sanctioned coach fan-out", {
  skip_if_not_installed("pointblank")
  backbone <- tibble::tibble(
    playerId = c("1", "2", "3"),
    season = c(2020L, 2020L, 2020L),
    team = c("IU", "IU", "Miami")
  )
  coaches <- tibble::tibble(
    school = c("IU", "IU", "Miami"),
    season = c(2020L, 2020L, 2020L),
    coach_id = c(10L, 11L, 20L)
  )
  # IU had 2 coaches in 2020 -> keys 1 and 2 fan out to 2 rows each.
  ps <- tibble::tibble(
    playerId = c("1", "1", "2", "2", "3"),
    season = 2020L,
    team = c("IU", "IU", "IU", "IU", "Miami"),
    coach_id = c(10L, 11L, 10L, 11L, 20L),
    coach_name = "x",
    games = 12L,
    wins = 6L,
    losses = 6L,
    srs = 1.0,
    sp_overall = 1.0,
    sp_defense = 1.0
  )
  expect_true(pointblank::all_passed(
    contract_coach_link(ps, backbone, coaches, stop_on_fail = FALSE)
  ))
  # Dropping a fanned-out row breaks the pinned row count.
  bad <- ps[-1, ]
  expect_false(pointblank::all_passed(
    contract_coach_link(bad, backbone, coaches, stop_on_fail = FALSE)
  ))
})

test_that("contract_tier_link asserts tiers preserved rows and are valid", {
  skip_if_not_installed("pointblank")
  ps_coach <- tibble::tibble(playerId = "1", season = 2020L, team = "IU")
  good <- ps_coach |> dplyr::mutate(tier = 3L, tier_label = "Power")
  expect_true(pointblank::all_passed(
    contract_tier_link(good, ps_coach, stop_on_fail = FALSE)
  ))
  bad <- good |> dplyr::mutate(tier = 4L)
  expect_false(pointblank::all_passed(
    contract_tier_link(bad, ps_coach, stop_on_fail = FALSE)
  ))
})

test_that("contract_reused_filter pins rows dropped to the reused ids", {
  skip_if_not_installed("pointblank")
  ps_draft <- tibble::tibble(
    playerId = c("1", "2"),
    season = c(2020L, 2020L),
    team = c("IU", "IU")
  )
  good <- ps_draft |> dplyr::filter(playerId == "2")
  expect_true(pointblank::all_passed(
    contract_reused_filter(good, ps_draft, "1", stop_on_fail = FALSE)
  ))
  bad <- good |> dplyr::add_row(playerId = "3", season = 2020L, team = "IU")
  expect_false(pointblank::all_passed(
    contract_reused_filter(bad, ps_draft, "1", stop_on_fail = FALSE)
  ))
})

test_that("contract_change_features verifies flag definitions and row count", {
  skip_if_not_installed("pointblank")
  ps_pop <- tibble::tibble(
    playerId = c("1", "1"),
    season = c(2019L, 2020L),
    team = c("IU", "Miami"),
    coach_id = c(10L, 20L)
  )
  good <- ps_pop |>
    dplyr::mutate(
      prev_team = c(NA_character_, "IU"),
      prev_tier = c(NA_real_, 3),
      prev_coach_id = c(NA_real_, 10),
      transferred = c(FALSE, TRUE),
      transfer_direction = c(NA_character_, "up"),
      hc_changed = c(NA, TRUE),
      followed_coach = c(NA, FALSE)
    )
  expect_true(pointblank::all_passed(
    contract_change_features(good, ps_pop, stop_on_fail = FALSE)
  ))
  # Inconsistent flag fails (transferred says TRUE but teams match).
  bad <- good |> dplyr::mutate(team = c("IU", "IU"))
  expect_false(pointblank::all_passed(
    contract_change_features(bad, ps_pop, stop_on_fail = FALSE)
  ))
})

test_that("contract_roster guards key uniqueness and class_year range", {
  skip_if_not_installed("pointblank")
  good <- tibble::tibble(
    # Two teams in one season is legitimate (mid-season transfer); the key
    # includes team, so this passes.
    playerId = c("1", "1", "2"),
    season = c(2021L, 2021L, 2021L),
    team = c("Florida State", "Louisville", "USC"),
    height = c(74L, 74L, NA_integer_),
    weight = c(210L, 210L, NA_integer_),
    class_year = c(4L, 4L, NA_integer_)
  )
  expect_true(pointblank::all_passed(
    contract_roster(good, stop_on_fail = FALSE)
  ))
  # Exact duplicate row (same player-team-season twice) fails the key check.
  bad_key <- good |>
    dplyr::add_row(playerId = "2", season = 2021L, team = "USC")
  expect_false(pointblank::all_passed(
    contract_roster(bad_key, stop_on_fail = FALSE)
  ))
  # Season-valued class_year contamination (CFBD older seasons) fails the
  # range check; NA passes.
  bad_class <- good |> dplyr::mutate(class_year = c(2018L, 4L, NA_integer_))
  expect_false(pointblank::all_passed(
    contract_roster(bad_class, stop_on_fail = FALSE)
  ))
})

test_that("contract_roster_weight asserts row preservation and range", {
  skip_if_not_installed("pointblank")
  ps_change <- tibble::tibble(
    playerId = c("1", "2"),
    season = 2020L,
    team = "IU"
  )
  good <- ps_change |> dplyr::mutate(weight = c(210L, NA_integer_))
  expect_true(pointblank::all_passed(
    contract_roster_weight(good, ps_change, stop_on_fail = FALSE)
  ))
  bad <- good |> dplyr::mutate(weight = c(23L, NA_integer_))
  expect_false(pointblank::all_passed(
    contract_roster_weight(bad, ps_change, stop_on_fail = FALSE)
  ))
})

test_that("contract_recruit_link asserts the name guard leaves no HS values", {
  skip_if_not_installed("pointblank")
  player_season <- tibble::tibble(
    playerId = c("1", "2"),
    season = 2020L,
    team = "IU"
  )
  good <- player_season |>
    dplyr::mutate(
      recruit_matched = c(TRUE, FALSE),
      hs_class = c(2019L, NA_integer_),
      hs_stars = c(4L, NA_integer_),
      hs_rating = c(0.9, NA_real_),
      hs_national_rank = c(50L, NA_integer_)
    )
  expect_true(pointblank::all_passed(
    contract_recruit_link(good, player_season, stop_on_fail = FALSE)
  ))
  # An unmatched row carrying HS values violates the name guard.
  bad <- good |> dplyr::mutate(hs_stars = c(4L, 3L))
  expect_false(pointblank::all_passed(
    contract_recruit_link(bad, player_season, stop_on_fail = FALSE)
  ))
})

test_that("contract_player_season_stats passes a valid wide table and flags violations", {
  skip_if_not_installed("pointblank")
  good <- tibble::tibble(
    playerId = c("1", "2"),
    player = c("A", "B"),
    season = c(2015L, 2015L),
    team = c("Alpha", "Alpha"),
    conference = c("SEC", "SEC"),
    position = c("QB", "RB"),
    passing_completions = c(300, NA),
    rushing_yds = c(0, 500)
  )
  expect_true(pointblank::all_passed(
    contract_player_season_stats(good, stop_on_fail = FALSE)
  ))
  bad_dup <- good |> dplyr::add_row(good[1, ])
  expect_false(pointblank::all_passed(
    contract_player_season_stats(bad_dup, stop_on_fail = FALSE)
  ))
  bad_inf <- good |> dplyr::mutate(rushing_yds = c(0, Inf))
  expect_false(pointblank::all_passed(
    contract_player_season_stats(bad_inf, stop_on_fail = FALSE)
  ))
})
