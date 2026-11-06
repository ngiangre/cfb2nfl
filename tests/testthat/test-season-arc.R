player_stats_fixture <- function() {
  tibble::tribble(
    ~season , ~playerId , ~player , ~team , ~category   , ~statType , ~stat ,
    2020L   , "p1"      , "Pat"   , "A"   , "rushing"   , "YDS"     , "30"  ,
    2021L   , "p1"      , "Pat"   , "A"   , "passing"   , "YDS"     , "100" ,
    2021L   , "p1"      , "Pat"   , "B"   , "passing"   , "YDS"     , "50"  ,
    2021L   , "p1"      , "Pat"   , "B"   , "passing"   , "TD"      , "1"   ,
    2022L   , "p1"      , "Pat"   , "B"   , "passing"   , "YDS"     , "300" ,
    2022L   , "p2"      , "Ray"   , "C"   , "defensive" , "TOT"     , "40"  ,
    2022L   , "p2"      , "Ray"   , "C"   , "defensive" , "SOLO"    , "10"
  )
}

test_that("season_arc sums a split season and indexes the career", {
  arc <- season_arc(player_stats_fixture(), "passing", "YDS")
  expect_equal(nrow(arc), 2L)
  p1 <- arc[arc$playerId == "p1", ]
  # Two teams in 2021 sum to 150; the larger share (A = 100) names the team.
  expect_equal(p1$value[p1$season == 2021L], 150)
  expect_equal(p1$team[p1$season == 2021L], "A")
  # Index counts all stats: 2020 (rushing only) is season 1.
  expect_equal(p1$season_index[p1$season == 2021L], 2L)
  expect_equal(p1$season_index[p1$season == 2022L], 3L)
})

test_that("build_season_arcs has one row per player-season-stat", {
  arcs <- build_season_arcs(player_stats_fixture())
  expect_false(
    anyDuplicated(arcs[c("playerId", "season", "category", "statType")]) > 0
  )
  expect_setequal(
    paste(arcs$category, arcs$statType),
    c("passing YDS", "defensive TOT", "rushing YDS")
  )
  expect_equal(nrow(arcs), 4L)
})

test_that("contract_season_arc passes on a clean build", {
  ps <- player_stats_fixture()
  agent <- contract_season_arc(build_season_arcs(ps), ps, stop_on_fail = FALSE)
  expect_true(pointblank::all_passed(agent))
})

test_that("contract_season_arc fails on a dropped player-season (row loss)", {
  ps <- player_stats_fixture()
  arcs <- build_season_arcs(ps)
  agent <- contract_season_arc(arcs[-1, ], ps, stop_on_fail = FALSE)
  expect_false(pointblank::all_passed(agent))
})

test_that("contract_season_arc aborts by default when it fails", {
  ps <- player_stats_fixture()
  arcs <- build_season_arcs(ps)
  expect_error(contract_season_arc(arcs[-1, ], ps))
})
