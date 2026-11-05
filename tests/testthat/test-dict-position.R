# The derived position_path dict must document exactly the columns and types
# that build_position_path() returns (decision 0021; same check as
# test-dict-derived.R, kept in its own file for the position work).

dict_type_to_typeof <- c(
  int32 = "integer",
  string = "character",
  double = "double",
  logical = "logical"
)

test_that("position_path dict matches build_position_path() output schema", {
  skip_if_not_installed("yaml")
  dict_dir <- system.file("dict", package = "cfb2nfl")
  skip_if(identical(dict_dir, ""), "installed dict/ not found")

  f <- list(
    roster = tibble::tibble(
      playerId = c("1", "1", "2"),
      season = c(2015L, 2016L, 2015L),
      team = c("X", "X", "Y"),
      position = c("QB", "QB", NA)
    ),
    recruiting = tibble::tibble(
      playerId = "1",
      recruit_name = "A",
      hs_class = 2014L,
      stars = 4L,
      rating = 0.9,
      national_rank = 10L,
      recruit_position = "PRO",
      committed_to = "X"
    ),
    player_season = tibble::tibble(playerId = "1", player = "A"),
    picks_nfl = tibble::tibble(
      playerId = "1",
      year = 2018L,
      name = "A",
      gsis_id = "g1",
      nfl_matched = TRUE
    ),
    nfl_draft_picks = tibble::tibble(gsis_id = "g1", position = "QB")
  )
  actual <- build_position_path(
    f$roster,
    f$recruiting,
    f$player_season,
    f$picks_nfl,
    f$nfl_draft_picks
  )

  dict <- yaml::read_yaml(file.path(dict_dir, "position_path.yml"))
  documented <- vapply(dict$columns, function(col) col$name, character(1))
  documented_type <- vapply(dict$columns, function(col) col$type, character(1))
  names(documented_type) <- documented

  actual_type <- vapply(actual, typeof, character(1))
  expect_setequal(documented, names(actual_type))
  common <- intersect(documented, names(actual_type))
  expect_equal(
    unname(dict_type_to_typeof[documented_type[common]]),
    unname(actual_type[common]),
    info = "position_path"
  )
})
