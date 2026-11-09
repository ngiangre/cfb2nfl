explorer_combine_fixture <- function() {
  tibble::tibble(
    season = c(2025L, 2025L, 2025L, 2026L),
    player_name = c("Starter", "Big Man", "Nobody", "Next Year"),
    pos = c("QB", "OT", "EDGE", "WR"),
    school = c("Texas", "Texas", "Alabama", "Texas"),
    height = c(75L, 78L, 76L, 72L),
    weight = c(220L, 315L, 250L, 190L),
    forty = c(4.6, 5.2, NA, 4.4),
    bench = c(NA, 30L, 20L, NA),
    vertical = c(32, 26, 34, 38),
    broad_jump = c(115, 100, 118, 125),
    cone = c(7, 7.8, NA, 6.9),
    shuttle = c(4.3, 4.8, NA, 4.1),
    draft_year = c(2025L, 2025L, NA, NA),
    draft_round = c(1L, 5L, NA, NA),
    draft_ovr = c(3L, 150L, NA, NA),
    draft_team = c("Chicago", "Denver", NA, NA),
    athlete_id = c("q1", "o1", NA, "w1"),
    link_method = c("draft_slot", "draft_slot", "unmatched", "name_school")
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
  expect_equal(nrow(x), 4L)
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

test_that("write_explorer_combine writes columns and the contract passes", {
  dir <- withr::local_tempdir()
  cb <- explorer_combine_fixture()
  x <- build_explorer_combine(cb, explorer_player_seasons_fixture())
  path <- write_explorer_combine(x, dir)
  back <- jsonlite::read_json(path)
  expect_equal(length(back$name), 4L)
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
