# player_dossier() must be interpretable AND faithful: stats grouped/labeled by
# phase, coaching coverage made explicit (not silent NA), a data-backed
# undrafted-signed outcome, and a provenance block.

fixture <- function() {
  player_stats <- tibble::tibble(
    playerId = "P1",
    player = "Test Passer",
    position = "QB",
    conference = c("SEC", "SEC", "Big Sky", "Big Sky"),
    season = c(2015L, 2015L, 2016L, 2016L),
    team = c("Alpha", "Alpha", "Beta", "Beta"),
    category = c("passing", "defensive", "passing", "rushing"),
    statType = c("TD", "TD", "TD", "YDS"),
    stat = c("20", "1", "8", "150")
  )
  roster <- tibble::tibble(
    playerId = "P1",
    season = c(2015L, 2016L),
    team = c("Alpha", "Beta"),
    position = "QB",
    height = 74,
    weight = c(210L, 210L),
    jersey = 10L,
    class_year = c(3L, 4L),
    home_state = "TX",
    home_city = "Town"
  )
  # Alpha 2015 has a head coach; Beta 2016 (FCS) has none -> coach_available FALSE.
  coaches <- tibble::tibble(
    coach_id = "c1",
    coach_name = "Head One",
    school = "Alpha",
    conference = "SEC",
    season = 2015L,
    games = 13L,
    wins = 9L,
    losses = 4L,
    srs = NA_real_,
    sp_overall = NA_real_,
    sp_offense = NA_real_,
    sp_defense = NA_real_
  )
  picks_nfl <- tibble::tibble(
    playerId = character(),
    year = integer(),
    round = integer(),
    overall = integer(),
    gsis_id = character()
  )
  recruiting <- tibble::tibble(
    playerId = "someone-else",
    recruit_name = "Other Person",
    stars = 4L,
    rating = 0.95,
    national_rank = 50L,
    hs_class = 2014L,
    recruit_position = "QB",
    committed_to = "Alpha"
  )
  nfl_rosters <- tibble::tibble(
    gsis_id = c("g1", "g1"),
    player_name = c("Test Passer", "Test Passer"),
    season = c(2017L, 2018L),
    nfl_team = "AAA",
    position = "QB",
    status = "ACT",
    years_exp = c(0L, 1L),
    height = 74,
    weight = 210L,
    college = "Alpha",
    rookie_year = 2017L
  )
  nfl_player_stats <- tibble::tibble(gsis_id = "g1", games = 10L)
  list(
    player_stats = player_stats,
    roster = roster,
    coaches = coaches,
    picks_nfl = picks_nfl,
    recruiting = recruiting,
    nfl_rosters = nfl_rosters,
    nfl_player_stats = nfl_player_stats
  )
}

build <- function(f) {
  player_dossier(
    "P1",
    f$player_stats,
    f$roster,
    f$coaches,
    f$picks_nfl,
    f$recruiting,
    f$nfl_rosters,
    f$nfl_player_stats
  )
}

test_that("stats are grouped and labeled by phase (TD disambiguated)", {
  d <- build(fixture())
  pass_td <- d$stats[
    d$stats$category == "passing" &
      d$stats$statType == "TD" &
      d$stats$season == 2015L,
  ]
  def_td <- d$stats[
    d$stats$category == "defensive" & d$stats$statType == "TD",
  ]
  expect_equal(pass_td$phase, "offense")
  expect_equal(pass_td$label, "Passing touchdowns")
  expect_equal(def_td$phase, "defense")
  expect_equal(def_td$label, "Defensive touchdowns")
})

test_that("missing coach is explicit (coach_available FALSE, not NA)", {
  d <- build(fixture())
  beta <- d$coaching[d$coaching$team == "Beta", ]
  expect_false(beta$coach_available)
  expect_false(is.na(beta$coach_available))
  alpha <- d$coaching[d$coaching$team == "Alpha", ]
  expect_true(alpha$coach_available)
})

test_that("an undrafted player shows undrafted-signed with longevity", {
  d <- build(fixture())
  expect_equal(d$outcome$nfl_status, "undrafted-signed")
  expect_equal(d$outcome$nfl_seasons, 2L)
})

test_that("provenance block flags coverage and unrated recruiting", {
  d <- build(fixture())
  expect_setequal(
    d$provenance$section,
    c("stats", "coaching", "recruiting", "outcome")
  )
  expect_false(isTRUE(d$recruiting$recruit_matched))
  coach_note <- d$provenance$note[d$provenance$section == "coaching"]
  expect_match(coach_note, "no CFBD head coach")
})

test_that("a drafted player resolves via the draft slot", {
  f <- fixture()
  f$picks_nfl <- tibble::tibble(
    playerId = "P1",
    year = 2017L,
    round = 1L,
    overall = 3L,
    gsis_id = "g1"
  )
  d <- build(f)
  expect_equal(d$outcome$nfl_status, "drafted")
  expect_equal(d$outcome$draft_overall, 3L)
})

test_that("career derived tables attach a career & eligibility section", {
  f <- fixture()
  # P1 spans 2015-2016 with one team change; add a no-stat 2014 that the
  # player returned from, the classic redshirt shape.
  f$roster <- rbind(
    f$roster[1, ] |> dplyr::mutate(season = 2014L, class_year = 1L),
    f$roster |> dplyr::mutate(class_year = class_year + 1L)
  )
  d <- player_dossier(
    "P1",
    f$player_stats,
    f$roster,
    f$coaches,
    f$picks_nfl,
    f$recruiting,
    f$nfl_rosters,
    f$nfl_player_stats,
    career = career_summary(f$roster),
    roster_flags = flag_redshirt(f$roster, f$player_stats)
  )
  expect_equal(d$career$seasons, 3L)
  expect_equal(d$career$transfers, 1L)
  expect_true(d$career$redshirt_career)
  expect_setequal(
    names(d$season_flags),
    c("season", "team", "class_year", "has_stats", "redshirt_season")
  )
  expect_true(d$season_flags$redshirt_season[d$season_flags$season == 2014L])
  # The career section is reported and caveated in the provenance block.
  expect_setequal(
    d$provenance$section,
    c("stats", "coaching", "recruiting", "outcome", "career")
  )
  expect_match(
    d$provenance$note[d$provenance$section == "career"],
    "redshirt-SHAPED"
  )
  expect_output(print(d), "Career & eligibility")
})

test_that("without derived tables the dossier is unchanged", {
  d <- build(fixture())
  expect_null(d$career)
  expect_null(d$season_flags)
  expect_setequal(
    d$provenance$section,
    c("stats", "coaching", "recruiting", "outcome")
  )
})
