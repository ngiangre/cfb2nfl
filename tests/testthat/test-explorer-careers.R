explorer_picks_nfl_fixture <- function() {
  tibble::tibble(
    year = c(2009L, 2025L, 2025L, 2026L, 2026L),
    round = c(1L, 1L, 6L, 1L, 2L),
    overall = c(1L, 3L, 190L, 1L, 40L),
    name = c("Too Early", "Starter", "Late Lineman", "Rookie", "Small School"),
    position = c(
      "Quarterback",
      "Quarterback",
      "Offensive Tackle",
      "Wide Receiver",
      "Defensive End"
    ),
    collegeTeam = c("Texas", "Texas", "Alabama", "Texas", "Ferris State"),
    collegeConference = c("Big 12", "SEC", "SEC", "SEC", "GLIAC"),
    playerId = c(NA, "q1", "o9", "w1", NA),
    gsis_id = c("g0", "g1", "g2", NA, "g4"),
    nfl_matched = c(TRUE, TRUE, TRUE, FALSE, TRUE)
  )
}

explorer_nfl_rosters_fixture <- function() {
  tibble::tibble(
    gsis_id = c("g0", "g1", "g1", "g1", "g4"),
    season = c(2010L, 2025L, 2026L, 2026L, 2026L)
  )
}

explorer_careers_tiers_fixture <- function() {
  tibble::tibble(
    season = c(2024L, 2025L, 2025L, 2026L),
    conference = c("SEC", "SEC", "Big 12", "SEC"),
    tier = c(3L, 3L, 3L, 3L),
    tier_label = "Power"
  )
}

explorer_careers_teams_fixture <- function() {
  ts <- build_explorer_team_season(
    explorer_games_fixture(),
    explorer_tiers_fixture()
  )
  build_explorer_teams(explorer_teams_fixture(), ts)
}

test_that("draft_position_group maps the draft's position names", {
  expect_equal(
    draft_position_group(c(
      "Quarterback",
      "Offensive Tackle",
      "Defensive Edge",
      "Outside Linebacker",
      "Safety",
      "Long Snapper",
      "Kick Returner",
      "Something New"
    )),
    c(
      "Quarterback",
      "Offensive line",
      "Defensive line",
      "Linebacker",
      "Defensive back",
      "Special teams",
      "Special teams",
      "Position not recorded"
    )
  )
})

test_that("build_explorer_draft keeps the data window and counts NFL seasons", {
  x <- build_explorer_draft(
    explorer_picks_nfl_fixture(),
    explorer_nfl_rosters_fixture(),
    explorer_careers_tiers_fixture(),
    explorer_careers_teams_fixture(),
    explorer_player_seasons_fixture()
  )
  # The 2009 draft predates the first season with tiers.
  expect_equal(nrow(x), 4L)
  by_name <- split(x, x$name)
  expect_equal(by_name$Starter$team_id, 1L)
  expect_equal(by_name$Starter$tier, 3L)
  # Two distinct roster seasons; on the latest roster, so still active.
  expect_equal(by_name$Starter$nfl_seasons, 2L)
  expect_true(by_name$Starter$active)
  expect_equal(by_name$Starter$players_pos, "QB")
  expect_equal(by_name$Starter$pos, "QB")
  # Linked to nflverse but never on a roster: zero seasons, not NA.
  expect_equal(by_name$`Late Lineman`$nfl_seasons, 0L)
  expect_false(by_name$`Late Lineman`$active)
  expect_equal(by_name$`Late Lineman`$pos, "OL")
  expect_true(is.na(by_name$`Late Lineman`$players_pos))
  # Not linked to nflverse: unknown seasons.
  expect_true(is.na(by_name$Rookie$nfl_seasons))
  expect_true(is.na(by_name$Rookie$active))
  # A conference absent from the tiers is tier 1; a school outside the
  # explorer's teams keeps its name and no id.
  expect_equal(by_name$`Small School`$tier, 1L)
  expect_true(is.na(by_name$`Small School`$team_id))
  expect_equal(by_name$`Small School`$team, "Ferris State")
})

test_that("explorer_tier_at uses the nearest season a conference has a tier", {
  tiers <- explorer_careers_tiers_fixture()
  expect_equal(
    explorer_tier_at(
      c("SEC", "SEC", "Big 12", "GLIAC", NA),
      c(2025L, 2009L, 2030L, 2025L, 2025L),
      tiers
    ),
    c(3L, 3L, 3L, 1L, 1L)
  )
})

explorer_ps_change_fixture <- function() {
  tibble::tibble(
    playerId = c("a", "a", "b", "b", "c"),
    season = c(2024L, 2025L, 2024L, 2025L, 2025L),
    team = c("Alabama", "Texas", "Texas", "Ferris State", "Texas"),
    transferred = c(FALSE, TRUE, FALSE, TRUE, TRUE),
    transfer_direction = c(NA, "lateral", NA, "down", "up")
  )
}

test_that("build_explorer_transfers counts arrivals by team, season and direction", {
  x <- build_explorer_transfers(
    explorer_ps_change_fixture(),
    explorer_careers_teams_fixture()
  )
  expect_equal(sum(x$n), 3L)
  tex <- x[x$team == "Texas", ]
  expect_equal(tex$team_id, c(1L, 1L))
  expect_setequal(tex$direction, c("lateral", "up"))
  ferris <- x[x$team == "Ferris State", ]
  expect_true(is.na(ferris$team_id))
  expect_equal(
    sum(x$n),
    sum(transfer_counts(explorer_ps_change_fixture())$n_transfers)
  )
})

test_that("write_explorer_careers writes columns and the contract passes", {
  dir <- withr::local_tempdir()
  picks_nfl <- explorer_picks_nfl_fixture()
  ps_change <- explorer_ps_change_fixture()
  careers <- build_explorer_careers(
    build_explorer_draft(
      picks_nfl,
      explorer_nfl_rosters_fixture(),
      explorer_careers_tiers_fixture(),
      explorer_careers_teams_fixture(),
      explorer_player_seasons_fixture()
    ),
    build_explorer_transfers(ps_change, explorer_careers_teams_fixture()),
    tibble::tibble(players = 10L, transferred = 2L, share = 0.2),
    explorer_nfl_rosters_fixture()
  )
  expect_equal(careers$nfl_latest_season, 2026L)
  path <- write_explorer_careers(careers, dir)
  back <- jsonlite::read_json(path)
  expect_equal(length(back$draft$name), 4L)
  expect_equal(back$transfer_rate$share, 0.2)
  expect_equal(back$nfl_latest_season, 2026L)
  expect_true(pointblank::all_passed(contract_explorer_careers(
    careers,
    picks_nfl,
    ps_change,
    2024L,
    path,
    stop_on_fail = FALSE
  )))
  short <- careers
  short$draft <- short$draft[-1, ]
  expect_false(pointblank::all_passed(contract_explorer_careers(
    short,
    picks_nfl,
    ps_change,
    2024L,
    path,
    stop_on_fail = FALSE
  )))
  expect_false(pointblank::all_passed(contract_explorer_careers(
    careers,
    picks_nfl,
    ps_change,
    2024L,
    path,
    max_gzip_bytes = 10L,
    stop_on_fail = FALSE
  )))
})
