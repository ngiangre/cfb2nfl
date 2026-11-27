# Shared builders for the head-coach and combine cards (feature F25, batch
# coaches-combine). Each card reads these instead of recomputing the same
# population, join or position grouping inline.

#' Draftees linked to the head coach of their college seasons
#'
#' One row per draftee-coach pair from [link_coaches_picks()], with the
#' draftee's position harmonized to the shared position groups. The `"last"`
#' rule keeps the coach of the draftee's final college season; `"any"` keeps
#' every coach of any season he played.
#'
#' @param picks,roster,coaches The `picks`, `roster` and `coaches` tables.
#' @param rule `"last"` (last school) or `"any"` (every season).
#' @param min_year First draft class kept.
#' @return A tibble of [link_coaches_picks()] columns plus `group`.
#' @export
coach_draftee_links <- function(
  picks,
  roster,
  coaches,
  rule = c("last", "any"),
  min_year = 2014L
) {
  rule <- rlang::arg_match(rule)
  link_coaches_picks(
    picks,
    roster,
    coaches,
    rule = rule,
    reused = reused_ids(roster)
  ) |>
    dplyr::filter(.data$year >= .env$min_year) |>
    dplyr::mutate(group = harmonize_position(.data$position, "picks"))
}

#' Head-coach tenure, and whether the coach produced a draftee
#'
#' Counts the seasons each head coach held the job in a window, with a
#' tenure bin, and flags the coaches whose draftees are in `producer_ids`.
#'
#' @param coaches The `coaches` table (`coach_id`, `season`).
#' @param producer_ids Coach ids with at least one draftee.
#' @param from,to The seasons the tenure counts (inclusive).
#' @return One row per coach active in the window: `coach_id`, `seasons`,
#'   `produced` and `tenure_bin` (an ordered factor).
#' @export
coach_tenure <- function(coaches, producer_ids, from = 2013L, to = 2025L) {
  coaches |>
    dplyr::filter(.data$season >= .env$from, .data$season <= .env$to) |>
    dplyr::distinct(.data$coach_id, .data$season) |>
    dplyr::count(.data$coach_id, name = "seasons") |>
    dplyr::mutate(
      produced = .data$coach_id %in% .env$producer_ids,
      tenure_bin = cut(
        .data$seasons,
        breaks = c(0, 1, 3, 6, 13),
        labels = c(
          "1 season",
          "2 to 3 seasons",
          "4 to 6 seasons",
          "7 or more seasons"
        )
      )
    )
}

#' Long combine measurables, one row per invitee and measurable
#'
#' @param combine The `combine` table.
#' @param measures [explorer_combine_measures()] (`key`, `label`).
#' @return `combine`'s identifying columns plus `position_group`, `key`,
#'   `label` (a factor in the measure order) and `value`.
#' @export
combine_measures_long <- function(combine, measures) {
  combine |>
    dplyr::mutate(
      position_group = factor(
        combine_position_group(.data$pos),
        position_group_levels()
      )
    ) |>
    dplyr::select(
      "season",
      "player_name",
      "school",
      "position_group",
      dplyr::all_of(measures$key)
    ) |>
    tidyr::pivot_longer(
      dplyr::all_of(measures$key),
      names_to = "key",
      values_to = "value"
    ) |>
    dplyr::left_join(dplyr::select(measures, "key", "label"), by = "key") |>
    dplyr::mutate(label = factor(.data$label, measures$label))
}

#' Invitees placed against the draft-eligible population, by position
#'
#' Joins each eligible season's roster position to [build_combine_funnel()],
#' so the invitation rates and draft rates can be split by position group.
#' A season with no recorded position is kept as "Position not recorded".
#'
#' @param combine The linked combine table.
#' @param outcomes The outcomes table.
#' @param roster The `roster` table (`playerId`, `season`, `position`).
#' @return [build_combine_funnel()] output with a `position_group` factor.
#' @export
combine_funnel_positions <- function(combine, outcomes, roster) {
  pos <- roster |>
    dplyr::distinct(.data$playerId, .data$season, .data$position) |>
    dplyr::distinct(.data$playerId, .data$season, .keep_all = TRUE)
  funnel <- build_combine_funnel(combine, outcomes) |>
    dplyr::left_join(
      pos,
      by = c("playerId", "season"),
      relationship = "many-to-one"
    )
  dplyr::mutate(
    funnel,
    position_group = factor(
      harmonize_position(.data$position, "roster"),
      c(position_group_levels(), "Position not recorded")
    )
  )
}

#' NFL rookies by position group and how they entered the league
#'
#' One row per rookie-season (a roster entry in the rookie year), routed as
#' `"Drafted"` when the player's id appears in the draft record and
#' `"Undrafted"` otherwise. Only rookie classes from `from` to `to` are kept,
#' so a season still being played is left out.
#'
#' @param nfl_rosters The `nfl_rosters` table (`gsis_id`, `season`,
#'   `position`, `rookie_year`).
#' @param nfl_draft_picks The `nfl_draft_picks` table (`gsis_id`).
#' @param from,to First and last rookie class kept.
#' @return A tibble: `gsis_id`, `rookie_year`, `group` (a position group)
#'   and `route`.
#' @export
nfl_rookie_routes <- function(
  nfl_rosters,
  nfl_draft_picks,
  from = 2014L,
  to = 2025L
) {
  drafted <- nfl_draft_picks |>
    dplyr::filter(!is.na(.data$gsis_id)) |>
    dplyr::distinct(.data$gsis_id) |>
    dplyr::pull(.data$gsis_id)
  nfl_rosters |>
    dplyr::filter(
      .data$season == .data$rookie_year,
      .data$rookie_year >= .env$from,
      .data$rookie_year <= .env$to,
      !is.na(.data$gsis_id),
      !is.na(.data$position)
    ) |>
    dplyr::distinct(.data$gsis_id, .data$position, .data$rookie_year) |>
    dplyr::mutate(
      group = harmonize_position(.data$position, "nfl_roster"),
      route = dplyr::if_else(
        .data$gsis_id %in% .env$drafted,
        "Drafted",
        "Undrafted"
      )
    ) |>
    dplyr::filter(.data$group %in% position_group_levels())
}
