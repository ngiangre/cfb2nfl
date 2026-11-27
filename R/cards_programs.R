# Shared computations for the programs and conferences cards (feature F25,
# batch "programs"): the draft and undrafted rates by group, conference
# realignment, stat-line coverage by division, and the expected draftees from
# a fitted win curve. Each was computed inline in the three posts they
# migrate from; one tested copy here serves every card.

#' Eligible, drafted and undrafted counts and their rates
#'
#' Summarises credited draft rows (`team_draft`, one row per school, season
#' and position group) by whatever groups the input is grouped by.
#'
#' @param d Credited rows with `team`, `n_eligible`, `n_drafted` and
#'   `n_udfa`, optionally grouped.
#' @return One row per group: `schools`, `eligible`, `drafted`, `udfa`,
#'   `draft_rate` and `udfa_rate` (shares of eligible players).
#' @export
draft_rates <- function(d) {
  d |>
    dplyr::summarise(
      schools = dplyr::n_distinct(.data$team),
      eligible = sum(.data$n_eligible),
      drafted = sum(.data$n_drafted),
      udfa = sum(.data$n_udfa),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      draft_rate = .data$drafted / .data$eligible,
      udfa_rate = .data$udfa / .data$eligible
    )
}

#' Conference changes by FBS school and season
#'
#' A conference change is an FBS school playing in a different conference, or
#' as an independent, than in its previous FBS season. The Pac-10 became the
#' Pac-12 in 2011, a rename rather than a move.
#'
#' @param fbs FBS team-seasons with `team`, `season` and `conference`.
#' @return One row per change: `team`, `season`, `from` (the previous league)
#'   and `league` (the new one).
#' @export
realignment_moves <- function(fbs) {
  fbs |>
    dplyr::mutate(
      league = dplyr::if_else(
        .data$conference == "Pac-10",
        "Pac-12",
        .data$conference
      )
    ) |>
    dplyr::arrange(.data$team, .data$season) |>
    dplyr::group_by(.data$team) |>
    dplyr::mutate(from = dplyr::lag(.data$league)) |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(.data$from), .data$from != .data$league) |>
    dplyr::select("team", "season", "from", "league")
}

#' Share of played teams with at least one player stat line, by division
#'
#' @param played Team-seasons that played at least one recorded game, with
#'   `classification`, `has_stat_lines`, `n_stat_players` and `n_roster`.
#' @return One row per season and division (`FBS`, `FCS`, `Division II and
#'   below`): teams played, teams with a stat line (`with_stats`), teams with
#'   a roster (`with_roster`), `share` and `roster_share` of the played teams,
#'   and the median players with a stat line (`depth`) and roster size
#'   (`roster_size`) among teams with a stat line or a roster.
#' @export
stat_coverage <- function(played) {
  division_order <- c("FBS", "FCS", "Division II and below")
  played |>
    dplyr::mutate(
      division = dplyr::case_when(
        .data$classification == "fbs" ~ "FBS",
        .data$classification == "fcs" ~ "FCS",
        TRUE ~ "Division II and below"
      ),
      division = factor(.data$division, levels = division_order)
    ) |>
    dplyr::group_by(.data$season, .data$division) |>
    dplyr::summarise(
      played = dplyr::n(),
      with_stats = sum(.data$has_stat_lines),
      with_roster = sum(.data$n_roster > 0),
      depth = stats::median(.data$n_stat_players[.data$has_stat_lines]),
      roster_size = stats::median(.data$n_roster[.data$n_roster > 0]),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      share = .data$with_stats / .data$played,
      roster_share = .data$with_roster / .data$played
    )
}

#' Fit a win-curve per tier
#'
#' One binomial logistic regression per tier, of drafted against eligible
#' players (`cbind(drafted, eligible - drafted)`) on one predictor.
#'
#' @param d Schools with `tier` (a factor or character), `drafted`,
#'   `eligible` and the predictor.
#' @param x The predictor's column name, e.g. `"win_pct"` or `"sp"`.
#' @return A named list of `glm` fits, one per tier.
#' @export
fit_tier_curves <- function(d, x) {
  f <- stats::as.formula(paste("cbind(drafted, eligible - drafted) ~", x))
  lapply(split(d, as.character(d$tier)), \(g) {
    stats::glm(f, family = stats::binomial, data = g)
  })
}

#' Expected and drafted-above-expected draftees per school
#'
#' Multiplies each school's eligible players by the rate its tier's curve
#' ([fit_tier_curves()]) predicts for its predictor.
#'
#' @param d Schools with `tier`, `drafted`, `eligible` and the predictor.
#' @param x The predictor's column name.
#' @return `d` with `expected_rate`, `expected` and `above` (drafted minus
#'   expected) added.
#' @export
expected_draftees <- function(d, x) {
  fits <- fit_tier_curves(d, x)
  tier <- as.character(d$tier)
  rate <- rep(NA_real_, nrow(d))
  for (t in names(fits)) {
    i <- tier == t
    rate[i] <- stats::predict(fits[[t]], newdata = d[i, ], type = "response")
  }
  d$expected_rate <- rate
  d$expected <- rate * d$eligible
  d$above <- d$drafted - d$expected
  d
}
