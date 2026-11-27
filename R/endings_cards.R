# Shared builders for the career-endings cards (feature F25), on top of the
# competing-outcomes functions (R/competing_outcomes.R).

#' Label career endings for the cards
#'
#' Orders `group` as a factor in the position-group order (plus "Position
#' not recorded") and names whether the player has a matched recruiting
#' record.
#'
#' @param endings Output of [career_endings()].
#' @return `endings` with `group` a factor and a `recruited` column.
#' @export
label_endings <- function(endings) {
  endings |>
    dplyr::mutate(
      group = factor(
        .data$group,
        c(position_group_levels(), "Position not recorded")
      ),
      recruited = dplyr::if_else(
        .data$hs_year_imputed,
        "No matched recruiting record",
        "Matched recruiting record"
      )
    )
}

#' Colours of the career endings
#'
#' One colour per ending, shared by every career-endings figure: the two NFL
#' routes carry the colour, the endings without the NFL stay grey.
#'
#' @return A named character vector, ending label to hex colour.
#' @export
ending_palette <- function() {
  c(
    "Drafted" = "#1B9E77",
    "Signed undrafted" = "#7570B3",
    "Eligibility ended, undrafted" = "#6B7280",
    "Left the data" = "#D1D5DB",
    "Still playing" = "#E5E7EB"
  )
}

#' Cumulative percent of each NFL route, and of either route
#'
#' [ending_incidence()] for drafted and signed undrafted, plus "either NFL
#' route" estimated as one ending so it carries its own interval.
#'
#' @param endings Output of [career_endings()].
#' @param by Grouping column, or `NULL` for everyone together.
#' @return [ending_incidence()] rows for states `drafted`, `signed_udfa` and
#'   `nfl`, with a reader-facing `route` factor.
#' @export
route_incidence <- function(endings, by = "group") {
  route_lab <- c(
    drafted = "Drafted",
    signed_udfa = "Signed undrafted",
    nfl = "Either NFL route"
  )
  either <- endings |>
    dplyr::mutate(
      ending = dplyr::if_else(
        .data$ending == "signed_udfa",
        "drafted",
        .data$ending
      )
    ) |>
    ending_incidence(by = by) |>
    dplyr::filter(.data$state == "drafted") |>
    dplyr::mutate(state = "nfl")
  ending_incidence(endings, by = by) |>
    dplyr::filter(.data$state %in% c("drafted", "signed_udfa")) |>
    dplyr::bind_rows(either) |>
    dplyr::mutate(route = factor(route_lab[.data$state], route_lab))
}

#' Position groups with too few players at risk to show
#'
#' @param ci [ending_incidence()] output by group.
#' @param horizon The eligible season the cards compare at.
#' @param min_risk Fewest players at risk for a group to be shown.
#' @return Character vector of group names.
#' @export
thin_position_groups <- function(ci, horizon, min_risk = 30) {
  ci |>
    dplyr::filter(.data$time == horizon, .data$n_risk < min_risk) |>
    dplyr::distinct(.data$group) |>
    dplyr::pull(.data$group) |>
    as.character()
}
