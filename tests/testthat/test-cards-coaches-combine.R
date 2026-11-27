# Shared builders for the head-coach and combine cards (feature F25).

coach_fixture <- function() {
  tibble::tibble(
    coach_id = c("c1", "c1", "c1", "c2", "c2", "c3"),
    coach_name = c("A", "A", "A", "B", "B", "C"),
    school = c("X", "X", "X", "Y", "Y", "Z"),
    season = c(2013L, 2014L, 2015L, 2013L, 2014L, 2013L)
  )
}

test_that("coach_tenure counts seasons in the window and flags producers", {
  ten <- coach_tenure(
    coach_fixture(),
    producer_ids = "c1",
    from = 2013L,
    to = 2015L
  )
  expect_setequal(ten$coach_id, c("c1", "c2", "c3"))
  expect_equal(ten$seasons[ten$coach_id == "c1"], 3L)
  expect_true(ten$produced[ten$coach_id == "c1"])
  expect_false(ten$produced[ten$coach_id == "c3"])
  expect_equal(
    as.character(ten$tenure_bin[ten$coach_id == "c2"]),
    "2 to 3 seasons"
  )
})

test_that("coach_tenure leaves seasons outside the window out", {
  ten <- coach_tenure(
    coach_fixture(),
    producer_ids = character(),
    from = 2014L,
    to = 2014L
  )
  expect_true(all(ten$seasons == 1L))
})

test_that("coach_draftee_links keeps the last-school coach and harmonizes positions", {
  picks <- tibble::tibble(
    playerId = c("p1", "p2"),
    year = c(2015L, 2015L),
    overall = c(10L, 11L),
    name = c("Ann", "Ben"),
    position = c("Wide Receiver", "Quarterback")
  )
  roster <- tibble::tibble(
    playerId = c("p1", "p1", "p2"),
    season = c(2013L, 2014L, 2014L),
    team = c("X", "Y", "X"),
    position = c("WR", "WR", "QB")
  )
  coaches <- tibble::tibble(
    coach_id = c("c1", "c2", "c1"),
    coach_name = c("A", "B", "A"),
    school = c("X", "Y", "X"),
    season = c(2013L, 2014L, 2014L)
  )
  links <- coach_draftee_links(
    picks,
    roster,
    coaches,
    rule = "last",
    min_year = 2014L
  )
  expect_equal(sort(links$playerId), c("p1", "p2"))
  expect_equal(links$coach_id[links$playerId == "p1"], "c2")
  expect_equal(links$group[links$playerId == "p1"], "Receiver")
  expect_equal(links$group[links$playerId == "p2"], "Quarterback")
})

test_that("combine_measures_long stacks each measurable under its label and group", {
  combine <- tibble::tibble(
    season = c(2022L, 2023L),
    player_name = c("a", "b"),
    school = c("X", "Y"),
    pos = c("QB", "WR"),
    height = c(74, NA),
    weight = c(210, 190),
    forty = c(NA, 4.5)
  )
  measures <- tibble::tibble(
    key = c("height", "weight", "forty"),
    label = c("Height", "Weight", "40-yard dash")
  )
  long <- combine_measures_long(combine, measures)
  expect_equal(nrow(long), 6L)
  expect_equal(
    as.character(long$position_group[long$player_name == "b"][1]),
    "Receiver"
  )
  expect_equal(sum(is.na(long$value)), 2L)
  expect_equal(levels(long$label), c("Height", "Weight", "40-yard dash"))
})

test_that("combine_funnel_positions places each eligible season by roster position", {
  outcomes <- tibble::tibble(
    playerId = c("a", "a", "b"),
    season = c(2020L, 2021L, 2020L),
    draft_year = c(2021L, 2022L, 2021L),
    draft_eligible = TRUE,
    outcome_observed_d = TRUE,
    outcome_drafted_d = c(TRUE, FALSE, FALSE)
  )
  combine <- tibble::tibble(
    season = 2021L,
    athlete_id = "a"
  )
  roster <- tibble::tibble(
    playerId = c("a", "a", "b"),
    season = c(2020L, 2021L, 2020L),
    position = c("QB", "QB", NA)
  )
  funnel <- combine_funnel_positions(combine, outcomes, roster)
  expect_equal(nrow(funnel), 3L)
  expect_true(funnel$invited[funnel$playerId == "a" & funnel$season == 2020L])
  expect_equal(
    as.character(funnel$position_group[funnel$playerId == "a"][1]),
    "Quarterback"
  )
  expect_equal(
    as.character(funnel$position_group[funnel$playerId == "b"]),
    "Position not recorded"
  )
})

test_that("nfl_rookie_routes routes rookies by the draft record and drops unfinished classes", {
  rosters <- tibble::tibble(
    gsis_id = c("g1", "g2", "g3", "g4", "g5"),
    season = c(2020L, 2020L, 2020L, 2026L, 2020L),
    rookie_year = c(2020L, 2020L, 2020L, 2026L, 2020L),
    position = c("QB", "WR", "K", "QB", "DB")
  )
  picks <- tibble::tibble(gsis_id = "g1")
  routes <- nfl_rookie_routes(rosters, picks, from = 2014L, to = 2025L)
  expect_setequal(routes$gsis_id, c("g1", "g2", "g3", "g5"))
  expect_equal(routes$group[routes$gsis_id == "g3"], "Special teams")
  expect_equal(routes$route[routes$gsis_id == "g1"], "Drafted")
  expect_equal(routes$route[routes$gsis_id == "g2"], "Undrafted")
  expect_equal(routes$group[routes$gsis_id == "g5"], "Defensive back")
})
