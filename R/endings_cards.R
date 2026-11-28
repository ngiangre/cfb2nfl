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
#' routes carry the colour, the endings without the NFL stay pale grey.
#'
#' @return A named character vector, ending label to hex colour.
#' @export
ending_palette <- function() {
  c(
    "Drafted" = "#1B9E77",
    "Signed undrafted" = "#7570B3",
    "Eligibility ended, undrafted" = "#D1D5DB",
    "Left the data" = "#E5E7EB",
    "Still playing" = "#F3F4F6"
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

#' Colours of the study-population leaves
#'
#' [ending_palette()] with drafted split into shades of drafted green by
#' round (round 1 darkest), plus the three groups the flow chart sets aside
#' in greys.
#'
#' @return A named character vector, leaf label to hex colour, in stack order.
#' @export
leaf_palette <- function() {
  rounds <- grDevices::colorRampPalette(c("#0A4A37", "#1B9E77", "#B8E6D6"))(7)
  names(rounds) <- paste("Drafted, round", 1:7)
  ends <- ending_palette()
  c(
    rounds,
    ends[c(
      "Signed undrafted",
      "Eligibility ended, undrafted",
      "Still playing"
    )],
    "Position not recorded" = "#E5E7EB",
    "Ruled out" = "#4B5563",
    "Never draft-eligible" = "#9CA3AF"
  )
}

#' Every roster player on one leaf of the study-population flow chart
#'
#' The flow chart of the career-endings cards ends in leaves: never
#' draft-eligible, ruled out, position not recorded, and the study
#' population's endings. This puts each player on one, with drafted split by
#' round, dated by the player's final season on a college roster. The
#' position group is the first eligible season's for eligible players (as in
#' [career_endings()]), the NFL entry season's for those ruled out, and the
#' final roster season's for the never eligible.
#'
#' @inheritParams career_endings
#' @return One row per player in `outcomes`: `playerId`, `final_season`,
#'   `group` (factor), `leaf` (factor, [leaf_palette()] order) and `round`.
#' @export
population_leaves <- function(outcomes, roster_pos) {
  final <- outcomes |>
    dplyr::summarise(final_season = max(.data$season), .by = "playerId")
  endings <- career_endings(outcomes, roster_pos) |>
    dplyr::transmute(
      .data$playerId,
      .data$group,
      .data$round,
      leaf = dplyr::case_when(
        .data$group == "Position not recorded" ~ "Position not recorded",
        .data$ending == "drafted" ~ paste("Drafted, round", .data$round),
        .data$ending == "censored" ~ "Still playing",
        .default = ending_labels()[.data$ending]
      )
    )
  ruled_out <- never_eligible_entrants(outcomes, roster_pos) |>
    dplyr::transmute(.data$playerId, .data$group, leaf = "Ruled out")
  pos <- dplyr::distinct(
    roster_pos,
    .data$playerId,
    .data$season,
    .keep_all = TRUE
  )
  never <- final |>
    dplyr::anti_join(endings, by = "playerId") |>
    dplyr::anti_join(ruled_out, by = "playerId") |>
    dplyr::left_join(pos, by = c("playerId", "final_season" = "season")) |>
    dplyr::transmute(
      .data$playerId,
      group = position_group(.data$position),
      leaf = "Never draft-eligible"
    )
  out <- dplyr::bind_rows(endings, ruled_out, never) |>
    dplyr::inner_join(final, by = "playerId") |>
    dplyr::mutate(
      group = factor(
        .data$group,
        c(position_group_levels(), "Position not recorded")
      ),
      leaf = factor(.data$leaf, names(leaf_palette()))
    ) |>
    dplyr::select("playerId", "final_season", "group", "leaf", "round")
  stopifnot(
    nrow(out) == nrow(final),
    !anyDuplicated(out$playerId),
    !anyNA(out$leaf)
  )
  out
}
