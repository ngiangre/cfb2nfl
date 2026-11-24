test_that("link_drafted never adds rows when an id maps to multiple picks", {
  # CFBD reuses collegeAthleteId across eras; picks carries history back to
  # 1936, so one player-season id can match two picks (decision 0011).
  ps <- tibble::tibble(
    playerId = c("1", "1", "2"),
    season = c(2020L, 2021L, 2021L),
    team = c("Georgia", "Georgia", "Alabama")
  )
  picks <- tibble::tibble(
    playerId = c("1", "1", "2"),
    year = c(1972L, 2022L, 2023L),
    round = c(1L, 3L, 2L),
    overall = c(5L, 90L, 40L)
  )
  out <- link_drafted(ps, picks)
  # Strictly 1:1 on the backbone — no fan-out.
  expect_equal(nrow(out), nrow(ps))
})

test_that("link_drafted resolves a colliding id to the in-window pick", {
  ps <- tibble::tibble(playerId = "1", season = 2021L, team = "Georgia")
  picks <- tibble::tibble(
    playerId = c("1", "1"),
    year = c(1972L, 2022L),
    round = c(1L, 3L),
    overall = c(5L, 90L)
  )
  out <- link_drafted(ps, picks)
  expect_equal(out$draft_year, 2022L)
  expect_true(out$drafted)
})

test_that("link_drafted does not attribute a pre-window collision pick", {
  # An id whose only pick is historical (id reuse across eras) must not be
  # marked drafted for a modern player-season (decision 0011).
  ps <- tibble::tibble(playerId = "1", season = 2021L, team = "Georgia")
  picks <- tibble::tibble(
    playerId = "1",
    year = 1973L,
    round = 1L,
    overall = 5L
  )
  out <- link_drafted(ps, picks)
  expect_false(out$drafted)
  expect_true(is.na(out$draft_year))
})

test_that("player_trajectory assembles both stages and marks undrafted", {
  subjects <- tibble::tibble(
    who = c("Drafted Player", "Undrafted Player"),
    cfb_athlete_id = c("100", "200"),
    gsis_id = c("00-d", "00-u")
  )
  roster <- tibble::tibble(
    playerId = c("100", "200", "999"),
    season = c(2015L, 2016L, 2015L),
    team = c("Texas", "Texas A&M", "Other")
  )
  nfl_rosters <- tibble::tibble(
    gsis_id = c("00-d", "00-d", "00-u"),
    season = c(2018L, 2019L, 2021L),
    nfl_team = c("KC", "KC", "BUF")
  )
  nfl_draft_picks <- tibble::tibble(
    gsis_id = "00-d",
    season = 2018L,
    round = 3L,
    pick = 90L
  )

  out <- player_trajectory(subjects, roster, nfl_rosters, nfl_draft_picks)

  # Only subject ids; college + distinct NFL seasons (2 subjects: 1+2 and 1+1).
  expect_equal(nrow(out), 5L)
  expect_setequal(out$who, c("Drafted Player", "Undrafted Player"))
  expect_setequal(unique(out$stage), c("College", "NFL"))

  # Draft status is derived from the pick table, not asserted.
  drafted <- out[out$who == "Drafted Player", ]
  expect_true(all(drafted$drafted))
  expect_equal(unique(drafted$draft_year), 2018L)
  expect_equal(unique(drafted$draft_overall), 90L)

  undrafted <- out[out$who == "Undrafted Player", ]
  expect_false(any(undrafted$drafted))
  expect_true(all(is.na(undrafted$draft_year)))
})

test_that("player_trajectory errors when the registry lacks required keys", {
  bad <- tibble::tibble(who = "X", cfb_athlete_id = "1")
  expect_error(
    player_trajectory(bad, tibble::tibble(), tibble::tibble(), tibble::tibble())
  )
})

test_that("link_drafted accepts a following-spring (2026) draft", {
  ps <- tibble::tibble(playerId = "1", season = 2025L, team = "Georgia")
  picks <- tibble::tibble(
    playerId = "1",
    year = 2026L,
    round = 2L,
    overall = 40L
  )
  out <- link_drafted(ps, picks)
  expect_true(out$drafted)
  expect_equal(out$draft_year, 2026L)
})

test_that("link_drafted marks undrafted player-seasons and completes drafted", {
  ps <- tibble::tibble(
    playerId = c("1", "3"),
    season = c(2021L, 2021L),
    team = c("Georgia", "Troy")
  )
  picks <- tibble::tibble(
    playerId = "1",
    year = 2022L,
    round = 3L,
    overall = 90L
  )
  out <- link_drafted(ps, picks)
  expect_false(any(is.na(out$drafted)))
  expect_true(out$drafted[out$playerId == "1"])
  expect_false(out$drafted[out$playerId == "3"])
})

test_that("name_variant(initials = FALSE) needs more than a shared initial", {
  expect_true(name_variant(
    "Mitchell Trubisky",
    "Mitch Trubisky",
    initials = FALSE
  ))
  expect_true(name_variant("Mo Hurst", "Maurice Hurst", initials = FALSE))
  expect_true(name_variant(
    "Obo Okoronkwo",
    "Ogbonnia Okoronkwo",
    initials = FALSE
  ))
  expect_true(name_variant("Dawaune Smoot", "Dawuane Smoot", initials = FALSE))
  expect_false(name_variant("Donovan Smith", "Devon Smith", initials = FALSE))
  expect_false(name_variant(
    "Duke Johnson",
    "De'Andre Johnson",
    initials = FALSE
  ))
  # The default keeps the shared-initial rule the recruiting link relies on.
  expect_true(name_variant("Donovan Smith", "Devon Smith"))
})
