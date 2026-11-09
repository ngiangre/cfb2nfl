test_that("explorer_default_season is the latest season with a completed game", {
  g <- explorer_games_fixture()
  expect_equal(explorer_default_season(g), 2026L)
  # Preseason: the new season's only game is unplayed, so it falls back.
  g$completed[g$season == 2026L] <- FALSE
  expect_equal(explorer_default_season(g), 2025L)
  g$completed <- FALSE
  expect_error(explorer_default_season(g), "No completed games")
})

test_that("explorer_game_sides gives one row per team per completed game", {
  sides <- explorer_game_sides(explorer_games_fixture())
  expect_equal(nrow(sides), 2L * 5L)
  expect_setequal(
    names(sides),
    c(
      "game_id",
      "season",
      "start",
      "team_id",
      "conference",
      "classification",
      "points",
      "opp_points",
      "elo_post"
    )
  )
  g1 <- sides[sides$game_id == 1L, ]
  expect_equal(g1$points[g1$team_id == 2L], 27L)
  expect_equal(g1$opp_points[g1$team_id == 2L], 30L)
})


test_that("build_explorer_team_season keeps FBS/FCS sides and counts the record", {
  ts <- build_explorer_team_season(
    explorer_games_fixture(),
    explorer_tiers_fixture()
  )
  # Teams 4 and 5 are D-II; game 6 is unplayed. 2025: teams 1, 2, 3;
  # 2026: teams 1, 2.
  expect_false(any(ts$team_id %in% c(4L, 5L)))
  expect_equal(nrow(ts), 5L)
})

test_that("build_explorer_team_season gets W-L-T, end Elo and tier right", {
  ts <- build_explorer_team_season(
    explorer_games_fixture(),
    explorer_tiers_fixture()
  )
  t1 <- ts[ts$team_id == 1L & ts$season == 2025L, ]
  # Team 1 2025: beat 2 (30-27), tied 3 (20-20).
  expect_equal(c(t1$games, t1$wins, t1$losses, t1$ties), c(2L, 1L, 0L, 1L))
  # End Elo = postgame Elo after the last game with an Elo (game 3).
  expect_equal(t1$elo_end, 1600L)
  expect_equal(t1$tier, 3L)
  expect_equal(t1$classification, "fbs")
  t3 <- ts[ts$team_id == 3L, ]
  expect_true(is.na(t3$elo_end)) # FCS: no Elo
  expect_equal(t3$tier_label, "FCS and below")
  expect_equal(ts$wins + ts$losses + ts$ties, ts$games)
  expect_named(
    ts,
    c(
      "team_id",
      "season",
      "conference",
      "classification",
      "tier",
      "tier_label",
      "games",
      "wins",
      "losses",
      "ties",
      "elo_end",
      "win_pct"
    )
  )
})


test_that("build_explorer_teams keeps teams in the export with a valid color", {
  ts <- build_explorer_team_season(
    explorer_games_fixture(),
    explorer_tiers_fixture()
  )
  tm <- build_explorer_teams(explorer_teams_fixture(), ts)
  expect_setequal(tm$team_id, c(1L, 2L, 3L))
  expect_named(
    tm,
    c("team_id", "team", "mascot", "abbreviation", "color", "alt_color", "logo")
  )
  # "#null" is not a color: the shared fallback grey stands in.
  expect_equal(tm$color[tm$team_id == 3L], "#6b7280")
  expect_equal(tm$color[tm$team_id == 1L], "#bf5700")
})

test_that("explorer_sources names only tables that have a dictionary", {
  src <- explorer_sources()
  expect_true(all(c("team_view", "teams_landscape") %in% names(src)))
  dicts <- sub("\\.yml$", "", list.files(app_sys("dict"), "\\.yml$"))
  expect_true(all(unlist(src) %in% dicts))
  expect_true(all(lengths(src) >= 2L)) # keeps them JSON arrays
})

test_that("build_explorer_meta carries the default season and sources", {
  m <- build_explorer_meta(explorer_games_fixture())
  expect_equal(m$default_season, 2026L)
  expect_equal(m$seasons, c(2025L, 2026L))
  expect_equal(m$default_team, 251L)
  expect_equal(m$sources, explorer_sources())
  expect_equal(m$positions$key, explorer_positions()$key)
  expect_equal(
    m$positions$qualifier[m$positions$key == "passing_ypa"][[1]],
    "At least 100 pass attempts"
  )
  expect_true(is.na(m$positions$qualifier[[1]]))
  expect_equal(m$outcomes$outcome[[1]], "r1")
  expect_equal(m$combine_measures$key[1:3], c("height", "weight", "forty"))
  expect_true("OL" %in% m$combine_groups$pos)
})

test_that("explorer_json writes rows, nulls and scalars the page expects", {
  js <- explorer_json(tibble::tibble(a = c(1L, NA), b = c("x", NA)))
  expect_equal(as.character(js), '[{"a":1,"b":"x"},{"a":null,"b":null}]')
  meta <- explorer_json(list(default_season = 2026L, seasons = c(2025L, 2026L)))
  expect_equal(
    as.character(meta),
    '{"default_season":2026,"seasons":[2025,2026]}'
  )
  expect_gt(explorer_json_gzip_bytes(tibble::tibble(a = 1:10)), 0)
})

test_that("write_explorer_assets writes one JSON file per asset and returns paths", {
  dir <- withr::local_tempdir()
  paths <- write_explorer_assets(
    list(meta = list(default_season = 2026L), teams = tibble::tibble(a = 1L)),
    dir
  )
  expect_equal(basename(paths), c("meta.json", "teams.json"))
  expect_true(all(file.exists(paths)))
  expect_equal(
    jsonlite::read_json(file.path(dir, "meta.json"))$default_season,
    2026L
  )
})


test_that("contract_explorer_shell passes on consistent assets", {
  f <- explorer_shell_fixture()
  agent <- contract_explorer_shell(
    f$teams,
    f$team_season,
    f$meta,
    f$games,
    stop_on_fail = FALSE
  )
  expect_true(pointblank::all_passed(agent))
})

test_that("contract_explorer_shell catches row loss, stale meta and size", {
  f <- explorer_shell_fixture()
  # A dropped team-season breaks the no-silent-loss game count.
  expect_false(pointblank::all_passed(contract_explorer_shell(
    f$teams,
    f$team_season[-1, ],
    f$meta,
    f$games,
    stop_on_fail = FALSE
  )))
  # A team-season with no display row.
  expect_false(pointblank::all_passed(contract_explorer_shell(
    f$teams[f$teams$team_id != 1L, ],
    f$team_season,
    f$meta,
    f$games,
    stop_on_fail = FALSE
  )))
  # Meta that disagrees with the games.
  stale <- f$meta
  stale$default_season <- 2025L
  expect_false(pointblank::all_passed(contract_explorer_shell(
    f$teams,
    f$team_season,
    stale,
    f$games,
    stop_on_fail = FALSE
  )))
  # Over the first-view budget.
  expect_false(pointblank::all_passed(contract_explorer_shell(
    f$teams,
    f$team_season,
    f$meta,
    f$games,
    max_gzip_bytes = 10L,
    stop_on_fail = FALSE
  )))
  expect_error(
    contract_explorer_shell(
      f$teams,
      f$team_season,
      stale,
      f$games,
      stop_on_fail = TRUE
    ),
    "explorer_shell"
  )
})

test_that("contract_explorer_shell requires a known default team and contiguous seasons", {
  f <- explorer_shell_fixture()
  unknown_team <- f$meta
  unknown_team$default_team <- 999999L
  expect_false(pointblank::all_passed(contract_explorer_shell(
    f$teams,
    f$team_season,
    unknown_team,
    f$games,
    stop_on_fail = FALSE
  )))
  # A gap in the season menu (2024 missing between 2023 and 2026) fails.
  gap <- f$meta
  gap$seasons <- c(2023L, 2026L)
  expect_false(pointblank::all_passed(contract_explorer_shell(
    f$teams,
    f$team_season,
    gap,
    f$games,
    stop_on_fail = FALSE
  )))
})

test_that("build_explorer_teams blanks invalid alt colors", {
  ts <- build_explorer_team_season(
    explorer_games_fixture(),
    explorer_tiers_fixture()
  )
  tm <- build_explorer_teams(explorer_teams_fixture(), ts)
  expect_true(is.na(tm$alt_color[tm$team_id == 2L]))
  expect_equal(tm$alt_color[tm$team_id == 1L], "#ffffff")
})

test_that("FCS team-seasons missing from the tier lookup default to tier 1", {
  tiers <- explorer_tiers_fixture()
  tiers <- tiers[tiers$conference != "SWAC", ]
  ts <- build_explorer_team_season(explorer_games_fixture(), tiers)
  t3 <- ts[ts$team_id == 3L, ]
  expect_equal(t3$tier, c(1L))
  expect_equal(t3$tier_label, "FCS and below")
  expect_false(anyNA(ts$tier))
})

test_that("contract_explorer_shell requires logos only for current programs", {
  f <- explorer_shell_fixture()
  # Team 3 plays only in 2025 (default season 2026): a missing logo is fine.
  past <- f$teams
  past$logo[past$team_id == 3L] <- NA
  expect_true(pointblank::all_passed(contract_explorer_shell(
    past,
    f$team_season,
    f$meta,
    f$games,
    stop_on_fail = FALSE
  )))
  # Team 1 plays in the default season: a missing logo fails.
  current <- f$teams
  current$logo[current$team_id == 1L] <- NA
  expect_false(pointblank::all_passed(contract_explorer_shell(
    current,
    f$team_season,
    f$meta,
    f$games,
    stop_on_fail = FALSE
  )))
  # A missing color fails for any season.
  nocolor <- f$teams
  nocolor$color[nocolor$team_id == 3L] <- NA
  expect_false(pointblank::all_passed(contract_explorer_shell(
    nocolor,
    f$team_season,
    f$meta,
    f$games,
    stop_on_fail = FALSE
  )))
})

test_that("build_explorer_team_season carries win share for the FCS landscape", {
  ts <- build_explorer_team_season(
    explorer_games_fixture(),
    explorer_tiers_fixture()
  )
  t1 <- ts[ts$team_id == 1L & ts$season == 2025L, ]
  # One win and one tie in two games: ties count half.
  expect_equal(t1$win_pct, 0.75)
  expect_true(all(ts$win_pct >= 0 & ts$win_pct <= 1))
  expect_equal(names(ts)[ncol(ts)], "win_pct")
})
