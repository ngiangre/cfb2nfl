# Shared builders for the movement cards (feature F25): the transfer events
# behind the transfer cards and the same-group share behind the position
# cards.

transfer_direction_levels <- function() {
  c("To a higher tier", "Same tier", "To a lower tier")
}

transfer_tier_levels <- function() {
  c("FCS and below", "Group of Five", "Power")
}

#' The transfer events, with their direction and tiers
#'
#' One row per player-season at a school different from the player's previous
#' observed season (`ps_change`, `transferred`). The direction compares the
#' conference tiers of the two schools; the position group is the roster
#' position's group ([position_group()]).
#'
#' @param ps_change The `ps_change` table.
#' @return The transferred rows, with `direction`, `from_tier`, `to_tier` and
#'   `group` added.
#' @export
transfer_events <- function(ps_change) {
  tier_names <- c(`1` = "FCS and below", `2` = "Group of Five", `3` = "Power")
  direction_names <- c(
    up = "To a higher tier",
    lateral = "Same tier",
    down = "To a lower tier"
  )
  ps_change |>
    dplyr::filter(.data$transferred %in% TRUE) |>
    dplyr::mutate(
      direction = factor(
        unname(direction_names[.data$transfer_direction]),
        levels = transfer_direction_levels()
      ),
      from_tier = factor(
        unname(tier_names[as.character(.data$prev_tier)]),
        levels = transfer_tier_levels()
      ),
      to_tier = factor(
        unname(tier_names[as.character(.data$tier)]),
        levels = transfer_tier_levels()
      ),
      group = position_group(.data$position)
    )
}

#' Share of each season's players who were at a new school
#'
#' A transfer season counts as a share of the player-seasons in that season.
#' Seasons after `through` are left out, so a season still being played does
#' not bias the rate.
#'
#' @param ps_change The `ps_change` table.
#' @param through The last season to include (the last complete college
#'   season).
#' @return One row per season: `season`, `seasons`, `transfers` and `share`.
#' @export
transfer_share_by_season <- function(ps_change, through) {
  ps_change |>
    dplyr::filter(.data$season <= through) |>
    dplyr::group_by(.data$season) |>
    dplyr::summarise(
      seasons = dplyr::n(),
      transfers = sum(.data$transferred %in% TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(share = .data$transfers / .data$seasons)
}

#' How often each position group keeps the same group in the next stage
#'
#' Compares two harmonized position groups (see [harmonized_position_levels()])
#' for each player: `from` is the earlier stage's group, `to` the later one.
#' A row with no group, or "Position not recorded" at either stage, is left
#' out of the comparison.
#'
#' @param d A table with one row per player.
#' @param from,to Column names of the earlier and later group.
#' @return One row per `from` group, ordered by the share that kept the same
#'   group (lowest first): `group`, `recruits`, `stayed` and `share`.
#' @export
position_stay_by_group <- function(d, from, to) {
  unrecorded <- "Position not recorded"
  kept <- d |>
    dplyr::filter(
      !is.na(.data[[from]]),
      !is.na(.data[[to]]),
      .data[[from]] != unrecorded,
      .data[[to]] != unrecorded
    ) |>
    dplyr::transmute(
      group = .data[[from]],
      same = .data[[from]] == .data[[to]]
    )
  kept |>
    dplyr::group_by(.data$group) |>
    dplyr::summarise(
      recruits = dplyr::n(),
      stayed = sum(.data$same),
      .groups = "drop"
    ) |>
    dplyr::mutate(share = .data$stayed / .data$recruits) |>
    dplyr::arrange(.data$share)
}
