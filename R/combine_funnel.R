# The combine invite-to-draft funnel (issue #64): which draft-eligible players
# were invited, and how often each side was drafted. Invitees join the outcomes
# population on athlete id (never name); a combine season is the draft year it
# precedes. On the fly in the combine post (decision 0041).

# Observed, draft-eligible player-seasons: the funnel's denominator.
funnel_population <- function(outcomes) {
  outcomes |>
    dplyr::filter(.data$draft_eligible, .data$outcome_observed_d) |>
    dplyr::select("playerId", "season", "draft_year", "outcome_drafted_d")
}

#' Place each combine invitee against the draft-eligible population
#'
#' An invitee is `eligible` when their athlete id has an observed,
#' draft-eligible season whose following draft is the combine year;
#' `outside_population` when linked to an athlete id that has no such season
#' (no stat line that season, the eligibility clock says not yet, or the
#' draft has not happened); `unmatched` when the combine row has no athlete id.
#'
#' @param combine Cleaned, linked combine table (`season`, `athlete_id`).
#' @param outcomes The outcomes table (`playerId`, `draft_year`,
#'   `draft_eligible`, `outcome_observed_d`, `outcome_drafted_d`).
#' @return `combine` with a `funnel_status` column, one row per input row.
#' @export
combine_funnel_status <- function(combine, outcomes) {
  keys <- funnel_population(outcomes) |>
    dplyr::distinct(athlete_id = .data$playerId, season = .data$draft_year) |>
    dplyr::mutate(in_population = TRUE)
  combine |>
    dplyr::left_join(
      keys,
      by = c("athlete_id", "season"),
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      funnel_status = dplyr::case_when(
        is.na(.data$athlete_id) ~ "unmatched",
        .data$in_population %in% TRUE ~ "eligible",
        TRUE ~ "outside_population"
      ),
      in_population = NULL
    )
}

#' Build the combine invite-to-draft funnel
#'
#' One row per observed, draft-eligible player-season, flagged by whether the
#' player was a combine invitee that draft year. Unmatched invitees cannot be
#' placed and are not counted here (see [combine_funnel_status()]).
#'
#' @inheritParams combine_funnel_status
#' @return A tibble: `playerId`, `season`, `draft_year`, `invited`, `drafted`;
#'   one row per eligible outcomes row.
#' @export
build_combine_funnel <- function(combine, outcomes) {
  invitees <- combine |>
    dplyr::filter(!is.na(.data$athlete_id)) |>
    dplyr::distinct(playerId = .data$athlete_id, draft_year = .data$season) |>
    dplyr::mutate(invited = TRUE)
  funnel_population(outcomes) |>
    dplyr::left_join(
      invitees,
      by = c("playerId", "draft_year"),
      relationship = "many-to-one"
    ) |>
    dplyr::transmute(
      playerId = .data$playerId,
      season = .data$season,
      draft_year = .data$draft_year,
      invited = .data$invited %in% TRUE,
      drafted = as.logical(.data$outcome_drafted_d)
    )
}
