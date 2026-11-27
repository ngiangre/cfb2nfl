# Shared builders for the draft-outcome cards (feature F25): the eligible
# seasons every card counts over, and the outcome ledger, the card that
# graduated to the Analysis page.

#' Eligible seasons with a known draft outcome
#'
#' The risk set of the draft-outcome cards: every draft-eligible roster
#' season whose next draft has happened (`outcome_observed_d`), with missing
#' outcome flags read as "did not happen".
#'
#' @param outcomes The `outcomes` table.
#' @return `outcomes` filtered to the risk set.
#' @export
eligible_risk_set <- function(outcomes) {
  outcomes |>
    dplyr::filter(.data$draft_eligible, .data$outcome_observed_d) |>
    dplyr::mutate(
      dplyr::across(
        c("outcome_drafted_d", "outcome_signed_udfa_d", "outcome_nfl_entry_d"),
        \(x) dplyr::coalesce(x, FALSE)
      )
    )
}

#' How often eligible seasons end drafted, undrafted, or in the NFL
#'
#' @param risk The risk set ([eligible_risk_set()]).
#' @return One row per outcome: `outcome`, `events`, `at_risk`, `share` and
#'   its Wilson interval `lo`/`hi`.
#' @export
outcome_ledger <- function(risk) {
  events <- c(
    sum(risk$outcome_drafted_d),
    sum(risk$outcome_signed_udfa_d),
    sum(risk$outcome_nfl_entry_d)
  )
  n <- nrow(risk)
  ci <- vapply(events, \(x) wilson(x, n), numeric(2))
  tibble::tibble(
    outcome = c(
      "Drafted, any round",
      "Signed as an undrafted free agent",
      "NFL entry (drafted or undrafted)"
    ),
    events = as.integer(events),
    at_risk = n,
    share = events / n,
    lo = ci["lo", ],
    hi = ci["hi", ]
  )
}

#' Figure: the outcome ledger
#'
#' One bar per outcome with its 95% interval and its share labelled past the
#' whisker, the draft highlighted.
#'
#' @param ledger [outcome_ledger()] output.
#' @return A ggplot with `ggiraph` tooltips.
#' @export
plot_outcome_ledger <- function(ledger) {
  rlang::check_installed(c("ggplot2", "ggiraph"))
  d <- ledger |>
    dplyr::mutate(
      outcome = stats::reorder(.data$outcome, .data$share),
      drafted = .data$outcome == "Drafted, any round",
      tip = sprintf(
        "%s: %s of %s eligible seasons (%.1f%%, 95%% CI %.1f%% to %.1f%%)",
        .data$outcome,
        fmt(.data$events),
        fmt(.data$at_risk),
        100 * .data$share,
        100 * .data$lo,
        100 * .data$hi
      )
    )
  top <- ceiling(100 * max(d$hi) + 2)
  ggplot2::ggplot(d, ggplot2::aes(100 * .data$share, .data$outcome)) +
    ggiraph::geom_col_interactive(
      ggplot2::aes(
        fill = .data$drafted,
        tooltip = .data$tip,
        data_id = .data$outcome
      ),
      width = 0.65
    ) +
    ggplot2::geom_linerange(
      ggplot2::aes(xmin = 100 * .data$lo, xmax = 100 * .data$hi),
      linewidth = 0.8
    ) +
    ggplot2::geom_text(
      ggplot2::aes(x = 100 * .data$hi + 0.4, label = pct(.data$share)),
      hjust = 0,
      size = 6
    ) +
    ggplot2::scale_fill_manual(
      values = c(`TRUE` = "#1B9E77", `FALSE` = "grey65"),
      guide = "none"
    ) +
    # Whole-percent breaks, so every tick label is the value it marks.
    ggplot2::scale_x_continuous(
      breaks = seq(0, top, by = 2),
      labels = \(x) paste0(x, "%"),
      limits = c(0, top)
    )
}

#' The recurring named players
#'
#' The players the posts and cards use as running examples, keyed on CFBD
#' athlete id, never on name (recruiting ids collide, decision 0013).
#'
#' @return A named character vector, name to athlete id.
#' @export
running_cast <- function() {
  c(
    "Joe Burrow" = "3915511",
    "Cam Ward" = "4688380",
    "Jordan Travis" = "4360799",
    "Shane Buechele" = "4039034",
    "Kyle Allen" = "559681"
  )
}

#' Attach each eligible season's position group
#'
#' Joins the roster position listed for the player in that season (one row
#' per player-season: a mid-season move repeats the same position) and maps
#' it to its group with [position_group()].
#'
#' @param risk The risk set ([eligible_risk_set()]).
#' @param roster The `roster` table (`playerId`, `season`, `position`).
#' @return `risk` with `position` and `group`; no rows added or dropped.
#' @export
add_position_group <- function(risk, roster) {
  pos <- roster |>
    dplyr::distinct(.data$playerId, .data$season, .data$position) |>
    dplyr::distinct(.data$playerId, .data$season, .keep_all = TRUE)
  out <- risk |>
    dplyr::left_join(pos, by = c("playerId", "season")) |>
    dplyr::mutate(group = position_group(.data$position))
  stopifnot(nrow(out) == nrow(risk))
  out
}
