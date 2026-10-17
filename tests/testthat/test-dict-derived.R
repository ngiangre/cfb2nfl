# The derived tables (decision 0021) are not published parquet, so the
# published-schema drift test (test-dict.R) can't cover them. Instead, validate
# each derived dict against the feature function's OUTPUT schema on a fixture,
# so the dictionaries can never silently drift from the derived tables either.

# dict `type` token -> the R storage type (typeof) it must map to.
dict_type_to_typeof <- c(
  int32 = "integer",
  string = "character",
  double = "double",
  logical = "logical"
)

check_dict <- function(ds, actual) {
  dict_dir <- system.file("dict", package = "cfbstats")
  skip_if(identical(dict_dir, ""), "installed dict/ not found")

  dict <- yaml::read_yaml(file.path(dict_dir, paste0(ds, ".yml")))
  documented <- vapply(dict$columns, function(col) col$name, character(1))
  documented_type <- vapply(dict$columns, function(col) col$type, character(1))
  names(documented_type) <- documented

  actual_type <- vapply(actual, typeof, character(1))
  # Set equality both ways: no undocumented columns, no phantom entries.
  expect_setequal(documented, names(actual_type))

  common <- intersect(documented, names(actual_type))
  expect_equal(
    unname(dict_type_to_typeof[documented_type[common]]),
    unname(actual_type[common]),
    info = ds
  )
}

test_that("career_summary dict matches career_summary() output schema", {
  skip_if_not_installed("yaml")
  roster <- tibble::tibble(
    playerId = c("1", "1", "2"),
    season = c(2015L, 2016L, 2015L),
    team = c("Alpha", "Beta", "Alpha")
  )
  check_dict("career_summary", career_summary(roster))
})

test_that("roster_flags dict matches flag_redshirt() output schema", {
  skip_if_not_installed("yaml")
  # Full-fidelity roster fixture (all clean_roster columns), so the dict is
  # checked against the real pass-through schema, not a minimal slice.
  roster <- tibble::tibble(
    playerId = c("1", "1", "2"),
    season = c(2015L, 2016L, 2015L),
    class_year = c(1L, 2L, 3L),
    team = c("Alpha", "Beta", "Alpha"),
    position = "QB",
    height = 74L,
    weight = 210L,
    jersey = 10L,
    home_state = "TX",
    home_city = "Town"
  )
  player_stats <- tibble::tibble(
    playerId = c("1", "2"),
    season = c(2016L, 2015L)
  )
  check_dict("roster_flags", flag_redshirt(roster, player_stats))
})

test_that("ps_change dict matches add_change_features() output schema", {
  skip_if_not_installed("yaml")
  # Full-fidelity ps_draft fixture: every pass-through column of the link chain
  # (all ps_change columns minus the seven add_change_features() derives).
  ps_draft <- tibble::tibble(
    playerId = c("1", "1", "2"),
    player = "Test Player",
    season = c(2015L, 2016L, 2015L),
    team = c("Alpha", "Beta", "Alpha"),
    conference = c("SEC", "SEC", "SEC"),
    position = "QB",
    coach_id = c(1L, 1L, 1L),
    coach_name = "Head One",
    conference_coach = "SEC",
    games = 13L,
    wins = 9L,
    losses = 4L,
    srs = 5.1,
    sp_overall = 1.2,
    sp_offense = 0.9,
    sp_defense = 1.5,
    tier = c(3L, 3L, 3L),
    tier_label = "Power",
    draft_year = NA_integer_,
    draft_round = NA_integer_,
    draft_overall = NA_integer_,
    drafted = FALSE
  )
  check_dict("ps_change", add_change_features(ps_draft))
})

test_that("player_season_stats dict matches build_player_season_stats() output schema", {
  skip_if_not_installed("yaml")
  # The wide table's stat columns are dynamic (one per observed (category,
  # statType) pair), so the dict documents them with a <category>_<statType>
  # placeholder: check the identity columns exactly, and the pattern for the rest.
  dict_dir <- system.file("dict", package = "cfbstats")
  skip_if(identical(dict_dir, ""), "installed dict/ not found")
  dict <- yaml::read_yaml(file.path(dict_dir, "player_season_stats.yml"))
  documented <- vapply(dict$columns, function(col) col$name, character(1))
  identity <- documented[documented != "<category>_<statType>"]

  player_stats <- tibble::tibble(
    playerId = c("1", "1", "2"),
    player = "Test Player",
    season = c(2015L, 2015L, 2015L),
    team = "Alpha",
    conference = "SEC",
    position = "QB",
    category = c("passing", "rushing", "rushing"),
    statType = c("COMPLETIONS", "YDS", "TD"),
    stat = c("300", "500", "8")
  )
  wide <- build_player_season_stats(player_stats)
  expect_setequal(
    identity,
    c("playerId", "player", "season", "team", "conference", "position")
  )
  expect_setequal(
    setdiff(names(wide), identity),
    c("passing_completions", "rushing_yds", "rushing_td")
  )
  expect_equal(
    vapply(wide[identity], typeof, character(1)),
    c(
      playerId = "character",
      player = "character",
      season = "integer",
      team = "character",
      conference = "character",
      position = "character"
    )
  )
  expect_equal(typeof(wide$passing_completions), "double")
})
