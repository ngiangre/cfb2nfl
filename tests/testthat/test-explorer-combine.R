explorer_combine_fixture <- function() {
  tibble::tibble(
    season = c(2025L, 2025L, 2025L, 2026L, 2025L),
    player_name = c(
      "Starter",
      "Big Man",
      "Nobody",
      "Next Year",
      "Made Roster"
    ),
    pos = c("QB", "OT", "EDGE", "WR", "EDGE"),
    school = c("Texas", "Texas", "Alabama", "Texas", "Texas"),
    height = c(75L, 78L, 76L, 72L, 75L),
    weight = c(220L, 315L, 250L, 190L, 240L),
    forty = c(4.6, 5.2, NA, 4.4, 4.7),
    bench = c(NA, 30L, 20L, NA, 25L),
    vertical = c(32, 26, 34, 38, 31),
    broad_jump = c(115, 100, 118, 125, 112),
    cone = c(7, 7.8, NA, 6.9, 7.2),
    shuttle = c(4.3, 4.8, NA, 4.1, 4.5),
    draft_year = c(2025L, 2025L, NA, NA, NA),
    draft_round = c(1L, 5L, NA, NA, NA),
    draft_ovr = c(3L, 150L, NA, NA, NA),
    draft_team = c("Chicago", "Denver", NA, NA, NA),
    pfr_id = c("StaXX00", "BigXX00", NA, "NexXX00", "MadXX00"),
    athlete_id = c("q1", "o1", NA, "w1", NA),
    link_method = c(
      "draft_slot",
      "draft_slot",
      "unmatched",
      "name_school",
      "unmatched"
    )
  )
}

explorer_nfl_players_fixture <- function() {
  tibble::tibble(
    pfr_id = c("MadXX00", "NexXX00"),
    gsis_id = c("00-0000001", "00-0000002"),
    rookie_season = c(2021L, 2026L),
    last_season = c(2025L, 2026L)
  )
}

test_that("combine_position_group maps PFR codes onto the shared groups", {
  expect_equal(
    combine_position_group(c("OT", "EDGE", "OLB", "SAF", "K", "QB", "XX")),
    c(
      "Offensive line",
      "Defensive line",
      "Linebacker",
      "Defensive back",
      "Special teams",
      "Quarterback",
      "Position not recorded"
    )
  )
  expect_true(all(
    combine_position_group(c(
      "QB",
      "RB",
      "WR",
      "TE",
      "C",
      "DT",
      "LB",
      "CB",
      "P"
    )) %in%
      position_group_levels()
  ))
})

test_that("explorer_combine_groups adds OL to the Players groups, in order", {
  g <- explorer_combine_groups()
  expect_equal(g$group, position_group_levels())
  expect_equal(g$pos[g$group == "Offensive line"], "OL")
})

test_that("build_explorer_combine labels outcomes and links players", {
  x <- build_explorer_combine(
    explorer_combine_fixture(),
    explorer_player_seasons_fixture()
  )
  expect_equal(nrow(x), 5L)
  by_name <- split(x, x$name)
  expect_equal(by_name$Starter$outcome, "r1")
  expect_equal(by_name$Starter$outcome_label, "Drafted R1 #3 (Chicago)")
  expect_equal(by_name$Starter$players_pos, "QB")
  expect_equal(by_name$`Big Man`$pos, "OL")
  expect_equal(by_name$`Big Man`$outcome, "r4_7")
  # o1 has no Players-tab line, so no link group.
  expect_true(is.na(by_name$`Big Man`$players_pos))
  expect_equal(by_name$Nobody$outcome, "undrafted")
  expect_equal(by_name$Nobody$pos, "DL")
  # A class after the last draft with slots is pending, not undrafted.
  expect_equal(by_name$`Next Year`$outcome, "pending")
  expect_equal(by_name$`Next Year`$players_pos, "WR")
  expect_true(all(x$outcome %in% explorer_combine_outcome_levels()$outcome))
})

test_that("build_explorer_combine relabels UDFAs who made an NFL roster", {
  x <- build_explorer_combine(
    explorer_combine_fixture(),
    explorer_player_seasons_fixture(),
    nfl_players = explorer_nfl_players_fixture()
  )
  by_name <- split(x, x$name)
  # An undrafted invitee with an nflverse player record is a UDFA on a roster.
  expect_equal(by_name$`Made Roster`$outcome, "udfa")
  expect_equal(
    by_name$`Made Roster`$outcome_label,
    "UDFA, NFL roster (2021-2025)"
  )
  # Without a crosswalk row (or with no pfr_id) they stay Not drafted.
  expect_equal(by_name$Nobody$outcome, "undrafted")
  expect_equal(by_name$Nobody$outcome_label, "Not drafted")
  # Pending outranks the crosswalk: the draft has not happened yet.
  expect_equal(by_name$`Next Year`$outcome, "pending")
  expect_equal(
    by_name$`Next Year`$outcome_label,
    "Draft pending (draft not yet in the data)"
  )
  # A one-season career reads as a single year.
  one <- build_explorer_combine(
    explorer_combine_fixture() |>
      dplyr::mutate(
        pfr_id = dplyr::if_else(
          .data$player_name == "Made Roster",
          "OneXX00",
          .data$pfr_id
        )
      ),
    explorer_player_seasons_fixture(),
    nfl_players = explorer_nfl_players_fixture() |>
      dplyr::filter(.data$pfr_id != "MadXX00") |>
      dplyr::bind_rows(tibble::tibble(
        pfr_id = "OneXX00",
        gsis_id = "00-0000003",
        rookie_season = 2021L,
        last_season = 2021L
      ))
  )
  expect_equal(
    one$outcome_label[one$name == "Made Roster"],
    "UDFA, NFL roster (2021)"
  )
})

test_that("build_explorer_combine names the position a player was drafted at", {
  picks <- tibble::tibble(
    year = c(2025L, 2025L),
    overall = c(3L, 150L),
    position = c("Quarterback", "Offensive Guard")
  )
  x <- build_explorer_combine(
    explorer_combine_fixture(),
    explorer_player_seasons_fixture(),
    picks
  )
  by_name <- split(x, x$name)
  expect_equal(
    by_name$Starter$outcome_label,
    "Drafted as QB, R1 #3 (Chicago)"
  )
  # Worked out as a tackle, drafted as a guard.
  expect_equal(by_name$`Big Man`$combine_pos, "OT")
  expect_equal(
    by_name$`Big Man`$outcome_label,
    "Drafted as OG, R5 #150 (Denver)"
  )
  expect_equal(by_name$Nobody$outcome_label, "Not drafted")
})

test_that("write_explorer_combine writes columns and the contract passes", {
  dir <- withr::local_tempdir()
  cb <- explorer_combine_fixture()
  x <- build_explorer_combine(cb, explorer_player_seasons_fixture())
  path <- write_explorer_combine(x, dir)
  back <- jsonlite::read_json(path)
  expect_equal(length(back$name), 5L)
  expect_null(back$forty[[which(unlist(back$name) == "Nobody")]])
  expect_true(pointblank::all_passed(
    contract_explorer_combine(x, cb, path, stop_on_fail = FALSE)
  ))
  expect_false(pointblank::all_passed(
    contract_explorer_combine(x[-1, ], cb, path, stop_on_fail = FALSE)
  ))
  expect_false(pointblank::all_passed(contract_explorer_combine(
    x,
    cb,
    path,
    max_gzip_bytes = 10L,
    stop_on_fail = FALSE
  )))
})
