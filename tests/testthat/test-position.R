# Position harmonization and the per-player position path (issue #49).

test_that("harmonize_position maps every feed's codes into shared groups", {
  expect_equal(
    harmonize_position(c("QB", "PRO", "DUAL", "Quarterback"), "recruiting"),
    rep("Quarterback", 4)
  )
  expect_equal(
    harmonize_position(c("IOL", "OG", "OC", "OT", "T", "Center"), "roster"),
    rep("Offensive line", 6)
  )
  expect_equal(
    harmonize_position(c("EDGE", "SDE", "WDE", "Defensive Edge"), "picks"),
    rep("Defensive line", 4)
  )
  expect_equal(
    harmonize_position(
      c("SS", "FS", "SAF", "MLB", "Inside Linebacker"),
      "nfl_draft"
    ),
    c(
      "Defensive back",
      "Defensive back",
      "Defensive back",
      "Linebacker",
      "Linebacker"
    )
  )
  expect_equal(
    harmonize_position(c("APB", "FB"), "recruiting"),
    rep("Running back", 2)
  )
  expect_equal(
    harmonize_position(c("PK", "P", "LS", "KR"), "roster"),
    rep("Special teams", 4)
  )
  expect_equal(harmonize_position("ATH", "recruiting"), "Athlete")
})

test_that("blank and CFBD '?' positions become 'Position not recorded'", {
  expect_equal(
    harmonize_position(c(NA, "?"), "roster"),
    c("Position not recorded", "Position not recorded")
  )
})

test_that("an unmapped raw value is NA and is reported, never silently grouped", {
  expect_equal(harmonize_position("ZZ", "roster"), NA_character_)
  expect_equal(unmapped_positions(c("QB", "ZZ", NA, "ZZ"), "roster"), "ZZ")
  expect_length(unmapped_positions(c("QB", "WR"), "picks"), 0)
})

test_that("harmonize_position validates its source", {
  expect_error(harmonize_position("QB", "rosters"), "should be one of")
})

test_that("harmonized levels are the eleven reader-facing groups", {
  expect_length(harmonized_position_levels(), 11L)
  expect_true(all(
    harmonize_position(c("QB", "ATH", "?", "K"), "roster") %in%
      harmonized_position_levels()
  ))
})

# Fixture covering each join edge: a recruit linked by name, a recruit whose
# name disagrees at the same school (rejected: school never rescues a
# disagreeing name), a name variant at the same school (p5), a recruit with no
# college name linked by school + class year (p6) and one at another school
# (p7), a reused id, an id shared by two CFBD picks, and a draftee whose pick
# has no nflverse match.
position_fixture <- function() {
  roster <- tibble::tibble(
    playerId = c("p1", "p1", "p2", "p3", "p3", "p4", "p5", "p6", "p7"),
    season = c(2015L, 2016L, 2015L, 2015L, 2030L, 2016L, 2016L, 2015L, 2015L),
    team = c("X", "X", "Y", "Z", "Z", "W", "V", "U", "T"),
    position = c("QB", "QB", NA, "DE", "DE", "ATH", "OL", "WR", "LB")
  )
  recruiting <- tibble::tibble(
    playerId = c("p1", "p2", "p5", "p6", "p7"),
    recruit_name = c(
      "Alpha One",
      "Someone Else",
      "Evan Fivee",
      "Six Nameless",
      "Seven Elsewhere"
    ),
    hs_class = c(2014L, 2014L, 2016L, 2015L, 2015L),
    stars = c(4L, 3L, 3L, 2L, 2L),
    rating = c(0.9, 0.85, 0.8, 0.75, 0.75),
    national_rank = c(100L, 200L, 300L, 400L, 500L),
    recruit_position = c("PRO", "WR", "OT", "WR", "OLB"),
    committed_to = c("X", "Y", "V", "U", "Elsewhere")
  )
  player_season <- tibble::tibble(
    playerId = c("p1", "p2", "p3", "p4", "p5"),
    player = c("Alpha One", "Beta Two", "Gamma Three", "Dan Four", "Eve Five")
  )
  picks_nfl <- tibble::tibble(
    playerId = c("p1", "p4", "p4", "p5", NA),
    year = c(2018L, 2018L, 2019L, 2017L, 2017L),
    name = c("Alpha One", "Dan Four", "Dan Four", "Eve Five", "Nobody"),
    gsis_id = c("g1", "g2", "g3", NA, NA),
    nfl_matched = c(TRUE, TRUE, TRUE, FALSE, FALSE)
  )
  nfl_draft_picks <- tibble::tibble(
    gsis_id = c("g1", "g2", "g3", NA),
    position = c("QB", "DE", "OL", "OL")
  )
  list(
    roster = roster,
    recruiting = recruiting,
    player_season = player_season,
    picks_nfl = picks_nfl,
    nfl_draft_picks = nfl_draft_picks
  )
}

test_that("build_position_path chains HS, college and NFL groups per id", {
  f <- position_fixture()
  pp <- build_position_path(
    f$roster,
    f$recruiting,
    f$player_season,
    f$picks_nfl,
    f$nfl_draft_picks,
    reused = "p3"
  )
  expect_equal(nrow(pp), 6L)
  expect_false(anyDuplicated(pp$playerId) > 0)
  expect_false("p3" %in% pp$playerId)

  p1 <- pp[pp$playerId == "p1", ]
  expect_true(p1$hs_linked)
  expect_equal(p1$hs_link_method, "name")
  expect_equal(p1$hs_group, "Quarterback")
  expect_equal(p1$hs_class, 2014L)
  expect_equal(p1$college_first_group, "Quarterback")
  expect_equal(p1$college_last_group, "Quarterback")
  expect_equal(p1$college_modal_group, "Quarterback")
  expect_equal(p1$college_seasons, 2L)
  expect_false(p1$college_changed)
  expect_true(p1$drafted)
  expect_true(p1$nfl_linked)
  expect_equal(p1$nfl_group, "Quarterback")

  # A recruit whose name disagrees is rejected even at the same school.
  p2 <- pp[pp$playerId == "p2", ]
  expect_false(p2$hs_linked)
  expect_true(is.na(p2$hs_link_method))
  expect_true(is.na(p2$hs_group))
  expect_true(is.na(p2$hs_class))
  expect_equal(p2$college_groups, 0L)
  expect_true(is.na(p2$college_first_group))
  expect_false(p2$drafted)

  # Two CFBD picks share the id: drafted, but not slot-linked.
  p4 <- pp[pp$playerId == "p4", ]
  expect_true(p4$drafted)
  expect_false(p4$nfl_linked)
  expect_true(is.na(p4$nfl_group))
  expect_equal(p4$college_groups, 1L)
  expect_equal(p4$college_first_group, "Athlete")

  # A null gsis id on a draftee must not fan out to the null-id nflverse row.
  p5 <- pp[pp$playerId == "p5", ]
  expect_true(is.na(p5$nfl_group))
  expect_false(p5$nfl_linked)
  # "Eve Five" / "Evan Fivee" at the committed school in the class year.
  expect_equal(p5$hs_link_method, "name_variant")
  expect_equal(p5$hs_group, "Offensive line")

  # No college name: school + class year decides.
  p6 <- pp[pp$playerId == "p6", ]
  expect_equal(p6$hs_link_method, "school_year")
  expect_equal(p6$hs_group, "Receiver")
  p7 <- pp[pp$playerId == "p7", ]
  expect_false(p7$hs_linked)
  expect_true(is.na(p7$hs_group))
})

test_that("name_variant accepts nicknames and typos, not different people", {
  expect_true(name_variant("Chris Bispham", "Christopher Bispham"))
  expect_true(name_variant("Jaire Rawlison", "Jaire Rawlinson"))
  expect_true(name_variant("Justin Evans-Jenkins", "Justin Evans"))
  expect_true(name_variant("Adam Vinatieri Jr.", "AJ Vinatieri"))
  expect_false(name_variant("Chandler Smith", "Bryson Smith"))
  expect_false(name_variant("Cam Ward", "Xavier Ward"))
  expect_false(name_variant("Mason Blakemore", "Mason King"))
  expect_equal(name_variant(NA, "Joe Burrow"), NA)
})

test_that("recruit_link_method orders the guards and needs school + year", {
  m <- recruit_link_method(
    player = c(
      "Joe Burrow",
      "Chris Oliver",
      "Chris Oliver",
      NA,
      NA,
      "Cam Ward"
    ),
    recruit_name = c(
      "Joseph Burrow",
      "Christopher Oliver",
      "Christopher Oliver",
      "Any Recruit",
      "Any Recruit",
      "Xavier Ward"
    ),
    committed_to = c("Ohio State", "BGSU", "BGSU", "BGSU", "BGSU", "Miami"),
    hs_class = c(2015L, 2019L, 2019L, 2019L, 2015L, 2021L),
    first_season = c(2015L, 2019L, 2023L, 2021L, 2019L, 2021L),
    early_teams = list("Ohio State", "BGSU", "BGSU", "BGSU", "BGSU", "Miami")
  )
  # Joseph/Joe is a variant; the rest show each guard's boundary: a variant
  # four years late, a nameless recruit two years late (allowed) and four
  # years late (not), and a disagreeing name at the right school.
  expect_equal(
    m,
    c("name_variant", "name_variant", NA, "school_year", NA, NA)
  )
  expect_equal(
    recruit_link_method(
      "Joe Burrow",
      "Joe Burrow",
      "X",
      2015L,
      2030L,
      list("Y")
    ),
    "name"
  )
})

test_that("contract_position_path passes on a valid path and fails on bad counts", {
  f <- position_fixture()
  pp <- build_position_path(
    f$roster,
    f$recruiting,
    f$player_season,
    f$picks_nfl,
    f$nfl_draft_picks,
    reused = "p3"
  )
  ok <- contract_position_path(
    pp,
    n_universe = 6L,
    n_picks_universe = 2L,
    min_nfl_coverage = 0.4,
    n_recruits_universe = 5L,
    min_hs_coverage = 0.5,
    stop_on_fail = FALSE
  )
  expect_true(pointblank::all_passed(ok))

  # HS coverage below the floor fails.
  low_hs <- contract_position_path(
    pp,
    n_universe = 6L,
    n_picks_universe = 2L,
    min_nfl_coverage = 0.4,
    n_recruits_universe = 5L,
    stop_on_fail = FALSE
  )
  expect_false(pointblank::all_passed(low_hs))

  # Row count off the universe is silent row loss.
  lost <- contract_position_path(
    pp,
    n_universe = 9L,
    n_picks_universe = 2L,
    min_nfl_coverage = 0.4,
    stop_on_fail = FALSE
  )
  expect_false(pointblank::all_passed(lost))

  # Coverage below the floor fails.
  low <- contract_position_path(
    pp,
    n_universe = 6L,
    n_picks_universe = 100L,
    stop_on_fail = FALSE
  )
  expect_false(pointblank::all_passed(low))
})

test_that("contract_position_mapping flags an unmapped raw position", {
  good <- contract_position_mapping(
    list(roster = c("QB", "?"), recruiting = "PRO"),
    stop_on_fail = FALSE
  )
  expect_true(pointblank::all_passed(good))
  bad <- contract_position_mapping(
    list(roster = c("QB", "ZZ")),
    stop_on_fail = FALSE
  )
  expect_false(pointblank::all_passed(bad))
  expect_error(
    contract_position_mapping(list(roster = "ZZ")),
    "position_mapping"
  )
})

test_that("position_universe_counts excludes reused and shared-id picks", {
  f <- position_fixture()
  counts <- position_universe_counts(
    f$roster,
    f$picks_nfl,
    reused = "p3",
    recruiting = f$recruiting
  )
  expect_equal(counts$n_universe, 6L)
  expect_equal(counts$n_recruits_universe, 5L)
  # p1 (2018) and p5 (2017) are unique 2010+ picks in the universe; p4's two
  # shared picks are excluded.
  expect_equal(counts$n_picks_universe, 2L)
})
