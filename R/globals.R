#' @importFrom rlang .data
NULL

# Column names referenced via data-masking (dplyr) and pointblank::vars() read
# to R CMD check as undefined globals. Declare them to quiet the NOTE.
utils::globalVariables(c(
  "season",
  "conference",
  "tier",
  "tier_label",
  "has_tier",
  # pointblank::vars() targets in R/contracts.R
  "collegeAthleteId",
  "year",
  "round",
  "overall",
  "playerId",
  "seasons",
  "has_stats",
  "redshirt_season",
  "redshirt_career",
  "coach_id",
  "school",
  "weight",
  "team",
  "drafted",
  "gsis_id",
  "pick",
  "nfl_matched",
  "who",
  "stage",
  # pointblank::vars() targets for the stat-phase taxonomy contract
  "category",
  "statType",
  "phase",
  "label",
  "kind"
))
