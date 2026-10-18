# The data dictionaries in inst/dict/*.yml must document exactly the columns of
# their cleaned target schema, with matching types, so the dictionaries never
# silently drift from the pipeline (decision 0005). The published parquet now IS
# the cleaned target schema (decision 0018), so the dict is compared directly
# against the parquet columns/types. Skips when the data is unavailable (e.g.
# R CMD check without the data-latest release).

# dataset (dict file / `dataset` field) -> its published (cleaned) parquet.
dict_parquet <- c(
  picks = "picks.parquet",
  player_stats = "player_stats.parquet",
  coaches = "coaches.parquet",
  teams = "teams.parquet",
  roster = "roster.parquet",
  recruiting = "recruiting.parquet",
  games = "games.parquet",
  game_team_stats = "game_team_stats.parquet",
  game_player_stats = "game_player_stats.parquet",
  conference_tiers = "conference_tiers.parquet",
  nfl_draft_picks = "nfl_draft_picks.parquet",
  nfl_rosters = "nfl_rosters.parquet",
  nfl_player_stats = "nfl_player_stats.parquet"
)

# dict `type` token -> the R storage type (typeof) it must map to.
dict_type_to_typeof <- c(
  int32 = "integer",
  string = "character",
  double = "double",
  logical = "logical"
)

test_that("each inst/dict/*.yml documents exactly its cleaned target schema", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("yaml")

  data_dir <- test_path("..", "..", "data")
  skip_if_not(dir.exists(data_dir), "raw data/ not available")

  dict_dir <- system.file("dict", package = "cfbstats")
  skip_if(identical(dict_dir, ""), "installed dict/ not found")

  for (ds in names(dict_parquet)) {
    parquet <- file.path(data_dir, dict_parquet[[ds]])
    skip_if_not(file.exists(parquet), paste0("missing ", dict_parquet[[ds]]))

    cleaned <- arrow::read_parquet(parquet)
    actual_type <- vapply(cleaned, typeof, character(1))

    dict <- yaml::read_yaml(file.path(dict_dir, paste0(ds, ".yml")))
    documented <- vapply(dict$columns, function(col) col$name, character(1))
    documented_type <- vapply(
      dict$columns,
      function(col) col$type,
      character(1)
    )
    names(documented_type) <- documented

    # Set equality both ways: no undocumented columns, no phantom entries.
    expect_setequal(documented, names(actual_type))

    # Types must match on the columns present in both (aligned by name).
    common <- intersect(documented, names(actual_type))
    expected <- unname(dict_type_to_typeof[documented_type[common]])
    got <- unname(actual_type[common])
    expect_equal(
      got,
      expected,
      info = paste0(ds, ": ", paste(common, collapse = ", "))
    )
  }
})
