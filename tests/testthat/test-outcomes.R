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

test_that("an undrafted player with no roster match is FALSE, not NA", {
  d <- make_inputs()
  out <- build_outcomes(
    d$ps_pop,
    d$career,
    d$recruiting,
    d$picks_nfl,
    d$nfl_rosters,
    d$nfl_player_stats
  )
  # Ann Ex: observed, undrafted, no NFL link anywhere. The dict says
  # "else 0 (NA when censored)" — NA here would silently shrink naive
  # prevalence denominators (mean(na.rm = TRUE) reads 35% instead of 4.7%).
  ann <- out[out$playerId == "30", ]
  expect_false(is.na(ann$outcome_signed_udfa_d))
  expect_false(ann$outcome_signed_udfa_d)
  # Drafted players are FALSE by mutual exclusivity, not NA either.
  ward <- out[out$playerId == "10", ]
  expect_true(all(!is.na(ward$outcome_signed_udfa_d)))
  expect_false(any(ward$outcome_signed_udfa_d %in% TRUE))
  expect_false(is.na(ward$outcome_signed_udfa_d[ward$draft_year == 2025L]))
  # Censoring remains the only source of NA.
  c_out <- build_outcomes(
    d$ps_pop,
    d$career,
    d$recruiting,
    d$picks_nfl,
    d$nfl_rosters,
    d$nfl_player_stats,
    last_complete_draft = 2024L
  )
  expect_true(is.na(c_out$outcome_signed_udfa_d[
    c_out$playerId == "10" & c_out$draft_year == 2025L
  ]))
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

# ---- label fixes (#99) --------------------------------------------------------

run_outcomes <- function(d, ...) {
  build_outcomes(
    d$ps_pop,
    d$career,
    d$recruiting,
    d$picks_nfl,
    d$nfl_rosters,
    d$nfl_player_stats,
    last_complete_draft = 2025L,
    ...
  )
}

test_that("a draft after a final season with no stat line lands on the last stat row", {
  d <- make_inputs()
  # Wynn: stat lines 2014-2016, on the roster in 2017 without one, drafted
  # 2018. No row has draft_year 2018, so the pick lands on the 2016 row.
  d$ps_pop <- dplyr::bind_rows(
    d$ps_pop,
    ps(playerId = "40", player = "Isaiah Wynn", season = 2014:2016)
  )
  d$career <- dplyr::bind_rows(
    d$career,
    ps(playerId = "40", last_season = 2017L)
  )
  d$picks_nfl <- dplyr::bind_rows(
    d$picks_nfl,
    ps(
      playerId = "40",
      year = 2018L,
      round = 1L,
      overall = 23L,
      gsis_id = "00-4"
    )
  )
  out <- run_outcomes(d)
  wynn <- out[out$playerId == "40", ]
  expect_equal(wynn$outcome_drafted_d, c(FALSE, FALSE, TRUE))
  expect_equal(wynn$outcome_draft_round_d[3], 1L)
  expect_equal(
    wynn$status_end_of_season,
    c("continuing", "continuing", "drafted")
  )
  expect_true(all(wynn$nfl_entry_event))
})

test_that("an undrafted signing after a no-stat final season lands on the last stat row", {
  d <- make_inputs()
  # Bushman: stat lines 2018-2019, injured through 2020, signed 2021.
  d$ps_pop <- dplyr::bind_rows(
    d$ps_pop,
    ps(playerId = "50", player = "Matt Bushman", season = 2018:2019)
  )
  d$career <- dplyr::bind_rows(
    d$career,
    ps(playerId = "50", last_season = 2020L)
  )
  d$nfl_rosters <- dplyr::bind_rows(
    d$nfl_rosters,
    ps(gsis_id = "00-5", player_name = "Matt Bushman", season = 2021L)
  )
  out <- run_outcomes(d)
  bush <- out[out$playerId == "50", ]
  expect_equal(bush$outcome_signed_udfa_d, c(FALSE, TRUE))
  expect_equal(bush$status_end_of_season, c("continuing", "signed_udfa"))
})

test_that("an entry after the completeness cutoff stays censored, not flagged", {
  d <- make_inputs()
  d$ps_pop <- dplyr::bind_rows(
    d$ps_pop,
    ps(playerId = "40", player = "Isaiah Wynn", season = 2023L)
  )
  d$career <- dplyr::bind_rows(
    d$career,
    ps(playerId = "40", last_season = 2024L)
  )
  d$picks_nfl <- dplyr::bind_rows(
    d$picks_nfl,
    ps(
      playerId = "40",
      year = 2026L,
      round = 1L,
      overall = 23L,
      gsis_id = "00-4"
    )
  )
  out <- run_outcomes(d)
  # The outcome after his last season is decided in 2026, past the cutoff.
  wynn <- out[out$playerId == "40", ]
  expect_false(wynn$outcome_observed_d)
  expect_true(is.na(wynn$outcome_drafted_d))
  expect_equal(wynn$status_end_of_season, "censored")
})

test_that("a pick on an id outside the population links by name and school", {
  d <- make_inputs()
  d$ps_pop <- dplyr::bind_rows(
    dplyr::mutate(d$ps_pop, team = "Elsewhere"),
    ps(
      playerId = "60",
      player = "Zay Jones",
      season = 2015:2016,
      team = "East Carolina"
    )
  )
  d$career <- dplyr::bind_rows(
    d$career,
    ps(playerId = "60", last_season = 2016L)
  )
  d$picks_nfl <- dplyr::bind_rows(
    dplyr::mutate(d$picks_nfl, name = "Cam Ward", collegeTeam = "Miami"),
    # The pick carries a different CFBD id than the stat line.
    ps(
      playerId = "999",
      year = 2017L,
      round = 2L,
      overall = 37L,
      gsis_id = "00-6",
      name = "Zay Jones",
      collegeTeam = "East Carolina"
    )
  )
  # The name guard would also find him on a roster: drafted must win.
  d$nfl_rosters <- dplyr::bind_rows(
    d$nfl_rosters,
    ps(gsis_id = "00-6", player_name = "Zay Jones", season = 2017L)
  )
  out <- run_outcomes(d)
  zay <- out[out$playerId == "60", ]
  expect_equal(zay$outcome_drafted_d, c(FALSE, TRUE))
  expect_equal(zay$outcome_draft_pick_d[2], 37L)
  expect_false(any(zay$outcome_signed_udfa_d))
  expect_equal(unique(zay$gsis_id), "00-6")
})

test_that("the name+school fallback skips a pick with two candidates", {
  d <- make_inputs()
  d$ps_pop <- dplyr::bind_rows(
    dplyr::mutate(d$ps_pop, team = "Elsewhere"),
    ps(
      playerId = c("60", "61"),
      player = "Zay Jones",
      season = 2016L,
      team = "East Carolina"
    )
  )
  d$career <- dplyr::bind_rows(
    d$career,
    ps(playerId = c("60", "61"), last_season = 2016L)
  )
  d$picks_nfl <- dplyr::bind_rows(
    dplyr::mutate(d$picks_nfl, name = "Cam Ward", collegeTeam = "Miami"),
    ps(
      playerId = "999",
      year = 2017L,
      round = 2L,
      overall = 37L,
      gsis_id = "00-6",
      name = "Zay Jones",
      collegeTeam = "East Carolina"
    )
  )
  out <- run_outcomes(d)
  expect_false(any(out$outcome_drafted_d[out$playerId %in% c("60", "61")]))
})

test_that("the UDFA guard never links a drafted player's gsis or an NFL debut during college", {
  d <- make_inputs()
  d$ps_pop <- dplyr::bind_rows(
    d$ps_pop,
    # A namesake of a drafted player (Cam Ward, gsis 00-1, drafted 2025).
    ps(playerId = "70", player = "Cam Ward", season = 2022:2024),
    # A namesake already on an NFL roster while still playing college.
    ps(playerId = "80", player = "John Johnson", season = 2015:2017)
  )
  d$career <- dplyr::bind_rows(
    d$career,
    ps(playerId = c("70", "80"), last_season = c(2024L, 2017L))
  )
  d$nfl_rosters <- dplyr::bind_rows(
    d$nfl_rosters,
    ps(gsis_id = "00-8", player_name = "John Johnson", season = 2017:2018)
  )
  out <- run_outcomes(d)
  # "Cam Ward" now has two candidate ids in the population: the real one
  # keeps his pick, the namesake gets nothing.
  expect_false(any(out$outcome_signed_udfa_d[out$playerId == "70"]))
  expect_true(all(is.na(out$gsis_id[out$playerId == "70"])))
  expect_false(any(out$outcome_signed_udfa_d[out$playerId == "80"]))
  expect_false(any(out$nfl_entry_event[out$playerId == "80"]))
  expect_true(any(out$outcome_drafted_d[out$playerId == "10"]))
})

test_that("contract_outcomes passes the fixture and catches a lost entry row", {
  skip_if_not_installed("pointblank")
  d <- make_inputs()
  out <- run_outcomes(d)
  expect_true(pointblank::all_passed(
    contract_outcomes(out, d$ps_pop, d$picks_nfl, stop_on_fail = FALSE)
  ))
  # An entrant whose entry row was lost.
  bad <- out
  bad$outcome_signed_udfa_d[bad$playerId == "20"] <- FALSE
  bad$outcome_nfl_entry_d[bad$playerId == "20"] <- FALSE
  bad$outcome_made_roster_entry_year[bad$playerId == "20"] <- NA
  expect_false(pointblank::all_passed(
    contract_outcomes(bad, d$ps_pop, d$picks_nfl, stop_on_fail = FALSE)
  ))
  # A UDFA carrying a drafted player's gsis.
  bad2 <- out
  bad2$gsis_id[bad2$playerId == "20"] <- "00-1"
  expect_false(pointblank::all_passed(
    contract_outcomes(bad2, d$ps_pop, d$picks_nfl, stop_on_fail = FALSE)
  ))
})

test_that("a pick years after the last college season is not a late entry", {
  d <- make_inputs()
  # A recycled id: stat lines end in 2014, a pick on the same id in 2020.
  d$ps_pop <- dplyr::bind_rows(
    d$ps_pop,
    ps(playerId = "90", player = "Re Used", season = 2013:2014)
  )
  d$career <- dplyr::bind_rows(
    d$career,
    ps(playerId = "90", last_season = 2014L)
  )
  d$picks_nfl <- dplyr::bind_rows(
    d$picks_nfl,
    ps(
      playerId = "90",
      year = 2020L,
      round = 5L,
      overall = 150L,
      gsis_id = "00-9"
    )
  )
  out <- run_outcomes(d)
  expect_false(any(out$outcome_drafted_d[out$playerId == "90"]))
  expect_false(any(out$nfl_entry_event[out$playerId == "90"]))
})
