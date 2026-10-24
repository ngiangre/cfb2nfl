# build_outcomes() assembles the person-period dependent-variable table
# (decision 0032): eligibility clock, drafted / NFL-entry labels, and survival
# bookkeeping. Fixtures are small enough to verify every derived column by hand.

ps <- function(...) {
  tibble::tibble(...)
}

make_inputs <- function() {
  ps_pop <- ps(
    playerId = c("10", "10", "10", "20", "20", "30"),
    player = c(
      "Cam Ward",
      "Cam Ward",
      "Cam Ward",
      "Kyle Allen",
      "Kyle Allen",
      "Ann Ex"
    ),
    season = c(2022L, 2023L, 2024L, 2016L, 2017L, 2020L)
  )
  career <- ps(
    playerId = c("10", "20", "30"),
    seasons = c(3L, 2L, 1L),
    first_season = c(2022L, 2016L, 2020L),
    last_season = c(2024L, 2017L, 2020L),
    teams = c(1L, 1L, 1L),
    gap_seasons = c(0L, 0L, 0L),
    transfers = c(0L, 0L, 0L)
  )
  # Ann Ex: no recruiting row -> hs_grad_year imputed.
  recruiting <- ps(
    playerId = c("10", "20"),
    recruit_name = c("Cam Ward", "Kyle Allen"),
    hs_class = c(2021L, 2014L),
    stars = c(5L, 3L),
    rating = c(0.95, 0.8),
    national_rank = c(10L, 500L),
    recruit_position = c("QB", "QB"),
    committed_to = c("Miami", "Texas A&M")
  )
  picks_nfl <- ps(
    playerId = c("10"),
    year = 2025L,
    round = 1L,
    overall = 1L,
    gsis_id = "00-1"
  )
  nfl_rosters <- ps(
    gsis_id = c("00-1", "00-2", "00-2"),
    player_name = c("Cam Ward", "Kyle Allen", "Kyle Allen"),
    season = c(2025L, 2018L, 2019L),
    rookie_year = c(2025L, 2018L, 2018L)
  )
  nfl_player_stats <- ps(gsis_id = "00-2", season = 2018L, games = 3L)
  list(
    ps_pop = ps_pop,
    career = career,
    recruiting = recruiting,
    picks_nfl = picks_nfl,
    nfl_rosters = nfl_rosters,
    nfl_player_stats = nfl_player_stats
  )
}

test_that("rows match the population and the eligibility clock is right", {
  d <- make_inputs()
  out <- build_outcomes(
    d$ps_pop,
    d$career,
    d$recruiting,
    d$picks_nfl,
    d$nfl_rosters,
    d$nfl_player_stats
  )
  expect_equal(nrow(out), 6L)
  expect_setequal(out$playerId, c("10", "20", "30"))
  # Known hs_class: 2021 -> first eligible draft 2024 (years_since_hs >= 3),
  # i.e. first eligible season 2023.
  ward <- out[out$playerId == "10", ]
  expect_false(ward$draft_eligible[ward$season == 2022L])
  expect_true(ward$draft_eligible[ward$season == 2023L])
  expect_true(ward$draft_eligible[ward$season == 2024L])
  expect_equal(ward$eligible_season_index[ward$season == 2023L], 1L)
  expect_equal(ward$eligible_season_index[ward$season == 2024L], 2L)
  expect_true(all(is.na(ward$eligible_season_index[ward$season == 2022L])))
  expect_false(any(ward$hs_year_imputed))
  # Imputed clock: first stat season (2020) minus 1 = 2019 -> draft 2021 is
  # years_since_hs 2, so the single 2020 row is not yet eligible.
  ann <- out[out$playerId == "30", ]
  expect_true(ann$hs_year_imputed)
  expect_equal(ann$hs_grad_year, 2019L)
  expect_false(ann$draft_eligible)
})

test_that("drafted labels land only on the draft-season row", {
  d <- make_inputs()
  out <- build_outcomes(
    d$ps_pop,
    d$career,
    d$recruiting,
    d$picks_nfl,
    d$nfl_rosters,
    d$nfl_player_stats
  )
  ward <- out[out$playerId == "10", ]
  expect_true(ward$outcome_drafted_d[ward$draft_year == 2025L])
  expect_false(ward$outcome_drafted_d[ward$draft_year == 2024L])
  expect_equal(ward$outcome_draft_round_d[ward$draft_year == 2025L], 1L)
  expect_equal(ward$outcome_draft_pick_d[ward$draft_year == 2025L], 1L)
  expect_equal(ward$outcome_draft_round_group_d[ward$draft_year == 2025L], "r1")
  expect_equal(
    ward$outcome_nfl_entry_type_d[ward$draft_year == 2025L],
    "drafted_r1"
  )
  # Pre-draft rows: undrafted so far.
  expect_equal(
    ward$outcome_draft_round_group_d[ward$draft_year == 2024L],
    "undrafted"
  )
})

test_that("UDFA entry is name-guarded and mutually exclusive with drafted", {
  d <- make_inputs()
  out <- build_outcomes(
    d$ps_pop,
    d$career,
    d$recruiting,
    d$picks_nfl,
    d$nfl_rosters,
    d$nfl_player_stats
  )
  allen <- out[out$playerId == "20", ]
  expect_true(allen$outcome_signed_udfa_d[allen$draft_year == 2018L])
  expect_false(allen$outcome_signed_udfa_d[allen$draft_year == 2017L])
  expect_true(allen$outcome_nfl_entry_d[allen$draft_year == 2018L])
  expect_equal(
    allen$outcome_nfl_entry_type_d[allen$draft_year == 2018L],
    "udfa"
  )
  # The entry-year success labels.
  expect_true(allen$outcome_made_roster_entry_year[allen$draft_year == 2018L])
  expect_equal(
    allen$outcome_rookie_games_entry_year[allen$draft_year == 2018L],
    3L
  )
  expect_true(is.na(allen$outcome_made_roster_entry_year[
    allen$draft_year == 2017L
  ]))
  # A drafted player never gets signed_udfa.
  ward <- out[out$playerId == "10", ]
  expect_true(all(
    is.na(ward$outcome_signed_udfa_d) |
      !ward$outcome_signed_udfa_d
  ))
  # Fixed horizon: Kyle entered at d = 2018, so k = 1 marks the 2018 row.
  expect_true(allen$outcome_nfl_entry_by_d_plus_k[allen$draft_year == 2018L])
})

test_that("an ambiguous name match yields no UDFA label", {
  d <- make_inputs()
  # Two distinct gsis_ids share Kyle Allen's normalized name: no guess.
  d$nfl_rosters <- ps(
    gsis_id = c("00-2", "00-9"),
    player_name = c("Kyle Allen", "Kyle Allen"),
    season = c(2018L, 2018L),
    rookie_year = c(2018L, 2018L)
  )
  out <- build_outcomes(
    d$ps_pop,
    d$career,
    d$recruiting,
    d$picks_nfl,
    d$nfl_rosters,
    d$nfl_player_stats
  )
  allen <- out[out$playerId == "20", ]
  expect_true(all(
    is.na(allen$outcome_signed_udfa_d) |
      !allen$outcome_signed_udfa_d
  ))
  expect_false(any(allen$outcome_nfl_entry_d %in% TRUE))
  expect_equal(unique(allen$outcome_nfl_entry_type_d), "none")
})

test_that("administrative right-censoring NA's outcomes instead of zeroing", {
  d <- make_inputs()
  # Draft 2025 is not yet complete.
  out <- build_outcomes(
    d$ps_pop,
    d$career,
    d$recruiting,
    d$picks_nfl,
    d$nfl_rosters,
    d$nfl_player_stats,
    last_complete_draft = 2024L
  )
  ward <- out[out$playerId == "10", ]
  expect_false(ward$outcome_observed_d[ward$draft_year == 2025L])
  expect_true(is.na(ward$outcome_drafted_d[ward$draft_year == 2025L]))
  expect_true(is.na(ward$outcome_nfl_entry_d[ward$draft_year == 2025L]))
  expect_equal(ward$status_end_of_season[ward$draft_year == 2025L], "censored")
  # Earlier rows stay observed.
  expect_true(ward$outcome_observed_d[ward$draft_year == 2024L])
})

test_that("survival bookkeeping: statuses, event time, no silent fan-out", {
  d <- make_inputs()
  out <- build_outcomes(
    d$ps_pop,
    d$career,
    d$recruiting,
    d$picks_nfl,
    d$nfl_rosters,
    d$nfl_player_stats
  )
  ward <- out[out$playerId == "10", ]
  # Cam enters at draft 2025: years_to_nfl_entry = 2025 - 2021 = 4.
  expect_true(all(ward$nfl_entry_event))
  expect_equal(unique(ward$years_to_nfl_entry), 4L)
  expect_equal(
    ward$status_end_of_season,
    c(
      "continuing",
      "continuing",
      "drafted"
    )
  )
  # Kyle never drafted in the fixture? He IS a UDFA (roster match), so his
  # final-season row IS the entry row: signed_udfa, not exhausted_undrafted.
  allen <- out[out$playerId == "20", ]
  expect_equal(
    allen$status_end_of_season,
    c("continuing", "signed_udfa")
  )
  # Censored event time: last observed draft year 2018 - hs 2014 = 4.
  expect_equal(unique(allen$years_to_nfl_entry), 4L)
  expect_true(all(allen$nfl_entry_event))
  # Ann: single final season, undrafted, no NFL link — exhausted_undrafted.
  expect_equal(
    out$status_end_of_season[out$playerId == "30"],
    "exhausted_undrafted"
  )
  expect_false(any(duplicated(out[c("playerId", "season")])))
})
