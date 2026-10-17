test_that("build_duckdb bundles named tables into a queryable database", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tables <- list(
    picks = data.frame(playerId = c("1", "2"), drafted = c(TRUE, TRUE)),
    roster = data.frame(playerId = c("1", "3"), season = c(2015L, 2016L))
  )
  db <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db), add = TRUE)

  expect_equal(build_duckdb(tables, db), db)
  expect_true(file.exists(db))

  con <- DBI::dbConnect(duckdb::duckdb(), db, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # The bundle also carries generated metadata tables (decision 0027).
  expect_setequal(
    DBI::dbListTables(con),
    c("picks", "roster", "_schema_manifest", "_meta")
  )
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM picks")$n, 2L)
  # The database is queryable across tables on the shared player key.
  joined <- DBI::dbGetQuery(
    con,
    "SELECT r.season FROM roster r JOIN picks p ON r.playerId = p.playerId"
  )
  expect_equal(joined$season, 2015L)
})

test_that("build_duckdb rejects an unnamed table list", {
  skip_if_not_installed("duckdb")
  db <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db), add = TRUE)
  expect_error(build_duckdb(list(data.frame(x = 1)), db), "named")
})

test_that("build_duckdb rebuilds from scratch, dropping stale tables", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  db <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db), add = TRUE)
  build_duckdb(list(old = data.frame(x = 1L)), db)
  build_duckdb(list(new = data.frame(y = 2L)), db)

  con <- DBI::dbConnect(duckdb::duckdb(), db, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  expect_setequal(
    DBI::dbListTables(con),
    c("new", "_schema_manifest", "_meta")
  )
})

test_that("build_player_season_stats pivots long stats to wide player-season grain", {
  ps <- tibble::tibble(
    playerId = c("1", "1", "1", "2"),
    player = c("A", "A", "A", "B"),
    season = c(2015L, 2015L, 2015L, 2015L),
    team = c("Alpha", "Alpha", "Alpha", "Alpha"),
    conference = c("SEC", "SEC", "SEC", "SEC"),
    position = c("QB", "QB", "QB", "RB"),
    category = c("passing", "passing", "rushing", "rushing"),
    statType = c("COMPLETIONS", "TD", "YDS", "TD"),
    stat = c("300", "3", "500.5", "8")
  )
  wide <- build_player_season_stats(ps)
  expect_equal(nrow(wide), 2L)
  expect_setequal(
    names(wide),
    c(
      "playerId",
      "player",
      "season",
      "team",
      "conference",
      "position",
      "passing_completions",
      "passing_td",
      "rushing_yds",
      "rushing_td"
    )
  )
  expect_equal(wide$passing_completions[wide$playerId == "1"], 300)
  # Duplicate (category, statType) pairs are summed.
  ps_dup <- ps |> dplyr::add_row(ps[3, ] |> dplyr::mutate(stat = "100"))
  expect_equal(
    build_player_season_stats(ps_dup)$rushing_yds[1],
    600.5
  )
  # Pairs a player-season never logged are NA.
  expect_true(is.na(wide$passing_completions[wide$playerId == "2"]))
})

test_that("build_duckdb adds _schema_manifest, _meta and the ps_change view", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tables <- list(
    ps_change = data.frame(
      playerId = "1",
      season = 2015L,
      drafted = FALSE,
      draft_year = NA_integer_,
      draft_round = NA_integer_,
      draft_overall = NA_integer_
    )
  )
  db <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db), add = TRUE)
  build_duckdb(tables, db)

  con <- DBI::dbConnect(duckdb::duckdb(), db, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # _schema_manifest is generated from the dictionaries; ps_change has one,
  # so the manifest row is documented (undocumented names are covered by the
  # schema_manifest unit test below).
  manifest <- DBI::dbGetQuery(con, "SELECT * FROM _schema_manifest")
  expect_setequal(manifest$table_name, "ps_change")
  expect_true(manifest$documented[manifest$table_name == "ps_change"])
  # The leakage-safe view exists and drops the outcome columns.
  views <- DBI::dbGetQuery(
    con,
    "SELECT view_name FROM duckdb_views() WHERE NOT internal"
  )$view_name
  expect_setequal(views, "player_season_inputs")
  input_cols <- DBI::dbGetQuery(
    con,
    "SELECT column_name FROM duckdb_columns() WHERE table_name = 'player_season_inputs'"
  )$column_name
  expect_setequal(input_cols, c("playerId", "season"))
  # _meta records the completeness boundary.
  meta <- DBI::dbGetQuery(con, "SELECT * FROM _meta")
  expect_equal(nrow(meta), 1L)
  expect_type(meta$last_complete_cfb_season, "integer")
  expect_type(meta$last_complete_nfl_draft, "integer")
  expect_s3_class(meta$refreshed_at, "POSIXct")
})

test_that("schema_manifest reads grain/key from the dictionaries", {
  skip_if_not_installed("yaml")
  dict_dir <- system.file("dict", package = "cfbstats")
  m <- schema_manifest(c("picks", "no_such_table"), dict_dir = dict_dir)
  expect_true(m$documented[1])
  expect_false(m$documented[2])
  expect_match(m$grain_key[1], "key:")
  expect_equal(m$dict_file[1], file.path("inst", "dict", "picks.yml"))
  expect_true(is.na(m$grain_key[2]))
})

test_that("season-completeness helpers use the date cutoffs", {
  # March 1 is the CFB boundary; May 1 the NFL draft boundary.
  expect_equal(last_complete_cfb_season(as.Date("2026-10-17")), 2025L)
  expect_equal(last_complete_cfb_season(as.Date("2026-02-15")), 2024L)
  expect_equal(last_complete_cfb_season(as.Date("2027-03-01")), 2026L)
  expect_equal(last_complete_nfl_draft(as.Date("2026-10-17")), 2025L)
  expect_equal(last_complete_nfl_draft(as.Date("2026-04-15")), 2024L)
})

test_that("slim_audit_log drops the nested NA profile and keeps the scalars", {
  log <- data.frame(
    step = "clean_picks",
    na_by_col = I(list(data.frame(col = "x", n_na = 1L))),
    n_rows_out = 3L
  )
  slim <- slim_audit_log(log)
  expect_false("na_by_col" %in% names(slim))
  expect_equal(nrow(slim), 1L)
})
