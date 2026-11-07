# NFL combine (decision 0043): clean_combine standardizes the nflverse table;
# link_combine matches invitees to CFBD athlete ids in name-guarded tiers.

raw_combine <- function(...) {
  base <- tibble::tibble(
    season = 2020,
    draft_year = NA_real_,
    draft_team = NA_character_,
    draft_round = NA_real_,
    draft_ovr = NA_real_,
    pfr_id = NA_character_,
    cfb_id = NA_character_,
    player_name = "A Player",
    pos = "WR",
    school = "Alabama",
    ht = "6-1",
    wt = 200,
    forty = 4.5,
    bench = 15,
    vertical = 35,
    broad_jump = 120,
    cone = 7,
    shuttle = 4.2
  )
  over <- tibble::tibble(...)
  base <- base[rep(1, nrow(over)), ]
  base[names(over)] <- over
  base
}

test_that("clean_combine converts height, types drills, and nulls bad values", {
  out <- clean_combine(raw_combine(
    player_name = c("Tall One", "Typo", "Short"),
    ht = c("6-4", "6-2", NA),
    forty = c(4.4, 9.9, NA),
    wt = c(250, 20, 180)
  ))
  expect_equal(out$height, c(76L, 74L, NA))
  # Out-of-range values are data-entry errors, coerced to NA.
  expect_equal(out$forty, c(4.4, NA, NA))
  expect_equal(out$weight, c(250L, NA, 180L))
  expect_type(out$bench, "integer")
  expect_type(out$draft_ovr, "integer")
  expect_false(any(c("ht", "wt") %in% names(out)))
})

test_that("clean_combine nulls a draft slot from a different year", {
  # nflverse attaches draft info by name: a 2013 invitee can't be a 2019 pick.
  out <- clean_combine(raw_combine(
    season = c(2013, 2019),
    player_name = "Mike Edwards",
    school = c("Hawaii", "Kentucky"),
    draft_year = 2019,
    draft_round = 3,
    draft_ovr = 99,
    pfr_id = "EdwaMi01"
  ))
  expect_equal(out$draft_ovr, c(NA, 99L))
  expect_equal(out$draft_year, c(NA, 2019L))
  expect_equal(out$pfr_id, c(NA, "EdwaMi01"))
})

test_that("school_key reconciles PFR and CFBD school spellings", {
  expect_equal(school_key("Boston Col."), school_key("Boston College"))
  expect_equal(school_key("Ohio St."), school_key("Ohio State"))
  expect_equal(school_key("Miami (FL)"), school_key("Miami"))
  expect_equal(school_key("Mississippi"), school_key("Ole Miss"))
  expect_equal(school_key("San Jose State"), school_key("San José State"))
  expect_equal(school_key("Hawaii"), school_key("Hawai'i"))
  expect_equal(school_key("Citadel"), school_key("The Citadel"))
  expect_equal(school_key("East. Michigan"), school_key("Eastern Michigan"))
  expect_false(school_key("Miami (FL)") == school_key("Miami (OH)"))
  expect_false(school_key("Michigan") == school_key("Michigan State"))
  expect_true(is.na(school_key(NA_character_)))
})

# A small CFBD world: ids 1-3 have careers, id 9 is a dead pick id.
cfbd <- list(
  picks = tibble::tibble(
    year = c(2020L, 2020L, 2020L, 2020L, 2020L),
    round = 1L,
    overall = c(1L, 2L, 3L, 4L, 5L),
    name = c(
      "Joe Burrow",
      "Ezekiel Ansah",
      "Somebody Else",
      "Dead Id",
      "Twin Pick"
    ),
    playerId = c("1", "2", "3", "9", "8"),
    collegeTeam = c("LSU", "BYU", "Texas", "Iowa", "Texas")
  ),
  player_stats = tibble::tibble(
    playerId = c("1", "2", "3", "4", "5", "6", "7", "10", "11"),
    player = c(
      "Joe Burrow",
      "Ezekiel Ansah",
      "Somebody Else",
      "Undrafted Guy",
      "Same Name",
      "Same Name",
      "Old Timer",
      "Dead Id",
      "Gap Year"
    ),
    season = c(2019L, 2019L, 2019L, 2019L, 2019L, 2019L, 2015L, 2019L, 2017L),
    team = c(
      "LSU",
      "BYU",
      "Texas",
      "Ole Miss",
      "Oregon",
      "Oregon",
      "Iowa",
      "Iowa",
      "Utah"
    )
  ),
  nfl_draft_picks = tibble::tibble(
    season = 2020L,
    round = 1L,
    pick = c(1L, 2L),
    pfr_player_id = c("BurrJo01", "AnsaEz00")
  )
)
cfbd$roster <- dplyr::select(cfbd$player_stats, "playerId", "season", "team")

link <- function(
  combine,
  reused = character(),
  roster = cfbd$roster,
  player_stats = cfbd$player_stats
) {
  link_combine(
    combine,
    cfbd$picks,
    player_stats,
    roster,
    cfbd$nfl_draft_picks,
    reused = reused
  )
}

drafted_row <- function(name, school, ovr, pfr = NA_character_) {
  raw_combine(
    player_name = name,
    school = school,
    draft_year = 2020,
    draft_round = 1,
    draft_ovr = ovr,
    pfr_id = pfr
  )
}

test_that("tier 1 links drafted invitees by draft slot behind a name guard", {
  cmb <- clean_combine(dplyr::bind_rows(
    drafted_row("Joe Burrow", "LSU", 1, "BurrJo01"),
    # Nickname: the names disagree but the school rescues the slot.
    drafted_row("Ziggy Ansah", "BYU", 2, "WrongId"),
    # Name and school both disagree: the slot is not trusted.
    drafted_row("Not Him", "Alabama", 3)
  ))
  out <- link(cmb)
  expect_equal(out$athlete_id, c("1", "2", NA))
  expect_equal(out$link_method, c("draft_slot", "draft_slot", "unmatched"))
  expect_equal(out$pfr_agrees, c(TRUE, FALSE, NA))
})

test_that("tier 2 links by name + school + final season", {
  cmb <- clean_combine(raw_combine(
    player_name = c("Undrafted Guy", "Undrafted Guy", "Old Timer", "Gap Year"),
    # PFR spells it "Mississippi"; CFBD says "Ole Miss".
    school = c("Mississippi", "Alabama", "Iowa", "Utah")
  ))
  out <- link(cmb)
  # Wrong school; final season 2015 is too long before a 2020 combine; a
  # final season two years out (2017 -> 2020 is three) also fails.
  expect_equal(out$athlete_id, c("4", NA, NA, NA))
  expect_equal(
    out$link_method,
    c("name_school", "unmatched", "unmatched", "unmatched")
  )
})

test_that("ambiguous matches link nothing", {
  cmb <- clean_combine(dplyr::bind_rows(
    # Two CFBD ids share the name, school and final season.
    raw_combine(player_name = "Same Name", school = "Oregon"),
    # Two invitees claim one slot (nflverse attached one pick to namesakes).
    drafted_row("Somebody Else", "Texas", 3),
    drafted_row("Somebody Else", "Texas", 3) |> dplyr::mutate(pos = "OLB")
  ))
  out <- link(cmb)
  expect_equal(out$athlete_id[1], NA_character_)
  # The disputed slot is skipped; both rows then match the same id by name,
  # which is still one id per combine, so the colliding rows stay unlinked
  # unless exactly one remains.
  expect_true(all(out$link_method[2:3] != "draft_slot"))
  expect_equal(nrow(out), 3L)
})

test_that("a reused id only links near the draft", {
  cmb <- clean_combine(drafted_row("Joe Burrow", "LSU", 1))
  # Id 1 is flagged reused; its only seasons are a decade before the draft.
  old <- tibble::tibble(playerId = "1", season = 2008L, team = "LSU")
  out <- link(
    cmb,
    reused = "1",
    roster = old,
    player_stats = old |>
      dplyr::mutate(player = "Joe Burrow")
  )
  expect_equal(out$link_method, "unmatched")
  # With a final season the year before the draft it links.
  expect_equal(link(cmb, reused = "1")$athlete_id, "1")
})

test_that("a pick id absent from the college data yields to a name_school id", {
  cmb <- clean_combine(drafted_row("Dead Id", "Iowa", 4))
  out <- link(cmb)
  expect_equal(out$athlete_id, "10")
  expect_equal(out$link_method, "name_school")
})

test_that("link_combine preserves rows and adds the link columns", {
  cmb <- clean_combine(raw_combine(player_name = c("Nobody", "Undrafted Guy")))
  out <- link(cmb)
  expect_equal(nrow(out), nrow(cmb))
  expect_equal(
    names(out),
    c(names(cmb), "athlete_id", "link_method", "pfr_agrees")
  )
  expect_equal(link(cmb[0, ])$athlete_id, character())
})

test_that("contract_combine passes a clean link and catches violations", {
  cmb <- link(clean_combine(dplyr::bind_rows(
    drafted_row("Joe Burrow", "LSU", 1, "BurrJo01"),
    raw_combine(player_name = "Undrafted Guy", school = "Mississippi")
  )))
  expect_true(pointblank::all_passed(contract_combine(cmb, n_expected = 2L)))
  expect_false(pointblank::all_passed(
    contract_combine(cmb, n_expected = 3L, stop_on_fail = FALSE)
  ))
  bad <- cmb
  bad$forty[1] <- 9
  expect_error(contract_combine(bad), "combine")
  dup <- cmb
  dup$athlete_id[2] <- "1"
  expect_false(pointblank::all_passed(
    contract_combine(dup, stop_on_fail = FALSE)
  ))
  # Link-rate floor: an unlinked drafted invitee from 2013 on.
  low <- cmb
  low$athlete_id[1] <- NA
  low$link_method[1] <- "unmatched"
  expect_false(pointblank::all_passed(
    contract_combine(low, stop_on_fail = FALSE)
  ))
})

test_that("combine dict matches the link_combine() output schema", {
  skip_if_not_installed("yaml")
  out <- link(clean_combine(drafted_row("Joe Burrow", "LSU", 1, "BurrJo01")))
  dict <- yaml::read_yaml(app_sys("dict/combine.yml"))
  documented <- vapply(dict$columns, \(col) col$name, character(1))
  types <- vapply(dict$columns, \(col) col$type, character(1))
  to_typeof <- c(
    int32 = "integer",
    string = "character",
    double = "double",
    logical = "logical"
  )
  expect_setequal(documented, names(out))
  expect_equal(
    unname(to_typeof[types]),
    unname(vapply(out[documented], typeof, character(1)))
  )
})
