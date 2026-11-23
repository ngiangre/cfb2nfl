# Competing endings of a college career (feature F24): each draft-eligible
# player's career ends once, in one of four ways, on an eligible-season clock.
# Built on the fly from `outcomes` (decision 0041); NFL labels stay outcomes.

#' Reader-facing labels for the four career endings
#'
#' @return A named character vector: ending code to label, in plot order.
#' @export
ending_labels <- function() {
  c(
    drafted = "Drafted",
    signed_udfa = "Signed undrafted",
    exhausted_undrafted = "Eligibility ended, undrafted",
    left_data = "Left the data"
  )
}

#' One row per eligible player: when and how the college career ended
#'
#' Reduces the person-period `outcomes` table to its competing-risks form.
#' A player's ending is the status of his **final** eligible row: a
#' `left_data` row followed by later seasons is a missed season, not an
#' ending. Time is the eligible-season index of that row. Players whose final
#' row is `continuing` or `censored` are right-censored at the last eligible
#' season whose outcome is known (0 when none is, which drops them from every
#' risk set). The position group is the roster position in the first
#' eligible season.
#'
#' @param outcomes The `outcomes` table (see [build_outcomes()]).
#' @param roster_pos One row per `(playerId, season)` with `position`.
#' @return A tibble: `playerId`, `player`, `group`, `hs_year_imputed`,
#'   `time` (integer), `ending` (an [ending_labels()] code or `"censored"`),
#'   `round` (draft round, `NA` unless drafted) and `missed_season` (the
#'   career has a mid-career `left_data` row).
#' @export
career_endings <- function(outcomes, roster_pos) {
  elig <- outcomes |>
    dplyr::filter(.data$draft_eligible) |>
    dplyr::arrange(.data$playerId, .data$season)
  first_pos <- elig |>
    dplyr::slice_min(.data$season, n = 1, by = "playerId") |>
    dplyr::select("playerId", "season") |>
    dplyr::left_join(roster_pos, by = c("playerId", "season")) |>
    dplyr::distinct(.data$playerId, .keep_all = TRUE) |>
    dplyr::transmute(
      .data$playerId,
      group = position_group(.data$position)
    )
  out <- elig |>
    dplyr::summarise(
      player = dplyr::first(.data$player),
      hs_year_imputed = dplyr::first(.data$hs_year_imputed),
      final_status = dplyr::last(.data$status_end_of_season),
      final_index = dplyr::last(.data$eligible_season_index),
      observed_index = suppressWarnings(max(
        .data$eligible_season_index[.data$outcome_observed_d],
        0L
      )),
      round = dplyr::last(.data$outcome_draft_round_d),
      missed_season = any(
        .data$status_end_of_season[-dplyr::n()] == "left_data"
      ),
      .by = "playerId"
    ) |>
    dplyr::mutate(
      censored = .data$final_status %in% c("continuing", "censored"),
      ending = dplyr::if_else(.data$censored, "censored", .data$final_status),
      time = as.integer(dplyr::if_else(
        .data$censored,
        .data$observed_index,
        .data$final_index
      )),
      round = dplyr::if_else(
        .data$ending == "drafted",
        .data$round,
        NA_integer_
      )
    ) |>
    dplyr::left_join(first_pos, by = "playerId") |>
    dplyr::select(
      "playerId",
      "player",
      "group",
      "hs_year_imputed",
      "time",
      "ending",
      "round",
      "missed_season"
    )
  stopifnot(
    nrow(out) == dplyr::n_distinct(elig$playerId),
    all(out$ending %in% c(names(ending_labels()), "censored"))
  )
  out
}

#' NFL entrants the eligibility clock never makes eligible
#'
#' Players who were drafted or signed before their first draft-eligible
#' season by the clock (early entrants, or an estimated high-school year that
#' runs late). They enter no risk set, so the ending curves leave them out.
#'
#' @inheritParams career_endings
#' @return A tibble: `playerId`, `player`, `group`, `route` (`"drafted"` or
#'   `"signed_udfa"`).
#' @export
never_eligible_entrants <- function(outcomes, roster_pos) {
  never <- outcomes |>
    dplyr::summarise(
      eligible = any(.data$draft_eligible),
      entry_season = dplyr::first(
        .data$season[.data$outcome_nfl_entry_d %in% TRUE]
      ),
      route = dplyr::if_else(
        any(.data$outcome_drafted_d %in% TRUE),
        "drafted",
        "signed_udfa"
      ),
      player = dplyr::first(.data$player),
      .by = "playerId"
    ) |>
    dplyr::filter(!.data$eligible, !is.na(.data$entry_season))
  never |>
    dplyr::left_join(
      dplyr::distinct(
        roster_pos,
        .data$playerId,
        .data$season,
        .keep_all = TRUE
      ),
      by = c("playerId", "entry_season" = "season")
    ) |>
    dplyr::transmute(
      .data$playerId,
      .data$player,
      group = position_group(.data$position),
      .data$route
    )
}

#' Cumulative incidence of each career ending, by eligible season
#'
#' The Aalen-Johansen estimate (via [survival::survfit()] with a multi-state
#' outcome) of the share of a group's eligible players whose career has
#' ended each way by each eligible season, with 95% intervals. Each season's
#' shares plus the share still playing sum to one.
#'
#' @param endings Output of [career_endings()].
#' @param by Grouping column, or `NULL` for everyone together.
#' @param left_data `"competing"` (an ending of its own) or `"censored"`
#'   (the player's later outcome is treated as unknown).
#' @return A tibble: the `by` column, `time` (0 to the last season with
#'   players at risk), `state` (an [ending_labels()] code or `"playing"`),
#'   `estimate`, `lower`, `upper` and `n_risk` (players still playing going
#'   into that season, the same on every state's row).
#' @export
ending_incidence <- function(
  endings,
  by = "group",
  left_data = c("competing", "censored")
) {
  rlang::check_installed(
    "survival",
    reason = "for the Aalen-Johansen estimate."
  )
  left_data <- rlang::arg_match(left_data)
  states <- names(ending_labels())
  if (left_data == "censored") {
    endings$ending[endings$ending == "left_data"] <- "censored"
    states <- setdiff(states, "left_data")
  }
  endings <- dplyr::filter(endings, .data$time > 0L)
  groups <- if (is.null(by)) list(endings) else split(endings, endings[[by]])
  purrr::imap(groups, function(d, g) {
    present <- intersect(states, unique(d$ending))
    status <- factor(d$ending, levels = c("censored", present))
    fit <- suppressWarnings(survival::survfit(
      survival::Surv(d$time, status) ~ 1
    ))
    times <- seq_len(max(d$time))
    # The log-scale interval is undefined at a share of exactly 0 or 1, where
    # it collapses to the estimate.
    s <- suppressWarnings(summary(fit, times = times, extend = TRUE))
    cols <- match(c(present, "(s0)"), s$states)
    long <- function(m, nm) {
      m <- matrix(m[, cols], ncol = length(cols))
      colnames(m) <- c(present, "playing")
      tibble::as_tibble(m) |>
        dplyr::mutate(time = s$time) |>
        tidyr::pivot_longer(-"time", names_to = "state", values_to = nm)
    }
    n_risk <- vapply(times, \(t) sum(d$time >= t), integer(1))
    est <- long(s$pstate, "estimate") |>
      dplyr::left_join(long(s$lower, "lower"), by = c("time", "state")) |>
      dplyr::left_join(long(s$upper, "upper"), by = c("time", "state")) |>
      dplyr::left_join(
        tibble::tibble(time = times, n_risk = n_risk),
        by = "time"
      ) |>
      dplyr::mutate(
        lower = dplyr::if_else(
          is.finite(.data$lower),
          .data$lower,
          .data$estimate
        ),
        upper = dplyr::if_else(
          is.finite(.data$upper),
          .data$upper,
          .data$estimate
        )
      )
    start <- tibble::tibble(
      time = 0,
      state = c(present, "playing"),
      estimate = c(rep(0, length(present)), 1),
      lower = .data$estimate,
      upper = .data$estimate,
      n_risk = nrow(d)
    )
    out <- dplyr::bind_rows(start, est) |>
      dplyr::mutate(time = as.integer(.data$time))
    if (!is.null(by)) {
      out[[by]] <- g
      out <- dplyr::relocate(out, dplyr::all_of(by))
    }
    out
  }) |>
    purrr::list_rbind()
}

#' The drafted share from a drafted-only survival curve
#'
#' One minus the Kaplan-Meier curve when being drafted is the only event and
#' every other ending is treated as censoring. It overstates the drafted
#' share whenever other endings compete, because it assumes a player who
#' ended another way could still have been drafted later.
#'
#' @inheritParams ending_incidence
#' @return A tibble: the `by` column, `time`, `estimate`.
#' @export
naive_drafted <- function(endings, by = "group") {
  rlang::check_installed("survival", reason = "for the Kaplan-Meier estimate.")
  endings <- dplyr::filter(endings, .data$time > 0L)
  groups <- if (is.null(by)) list(endings) else split(endings, endings[[by]])
  purrr::imap(groups, function(d, g) {
    fit <- survival::survfit(
      survival::Surv(d$time, d$ending == "drafted") ~ 1
    )
    s <- summary(fit, times = seq_len(max(d$time)), extend = TRUE)
    out <- tibble::tibble(time = as.integer(s$time), estimate = 1 - s$surv)
    if (!is.null(by)) {
      out[[by]] <- g
      out <- dplyr::relocate(out, dplyr::all_of(by))
    }
    out
  }) |>
    purrr::list_rbind()
}

#' Per-season chance of each ending among players still playing
#'
#' The discrete-time cause-specific hazard: of the players still playing
#' going into eligible season `t`, the share whose career ends each way in
#' that season.
#'
#' @inheritParams ending_incidence
#' @return A tibble: the `by` column, `time`, `ending`, `at_risk`, `events`,
#'   `hazard`, and its 95% Wilson interval `lower` and `upper`.
#' @export
ending_hazards <- function(endings, by = "group") {
  endings <- dplyr::filter(endings, .data$time > 0L)
  times <- seq_len(max(endings$time))
  by_cols <- if (is.null(by)) character() else by
  at_risk <- purrr::map(times, \(t) {
    endings |>
      dplyr::filter(.data$time >= t) |>
      dplyr::count(dplyr::across(dplyr::all_of(by_cols)), name = "at_risk") |>
      dplyr::mutate(time = t)
  }) |>
    purrr::list_rbind()
  grid <- tidyr::expand_grid(at_risk, ending = names(ending_labels()))
  events <- endings |>
    dplyr::filter(.data$ending != "censored") |>
    dplyr::count(
      dplyr::across(dplyr::all_of(c(by_cols, "time", "ending"))),
      name = "events"
    )
  grid |>
    dplyr::left_join(events, by = c(by_cols, "time", "ending")) |>
    dplyr::mutate(
      events = dplyr::coalesce(.data$events, 0L),
      hazard = .data$events / .data$at_risk,
      # Wilson interval for a binomial share.
      centre = (.data$hazard + 1.96^2 / (2 * .data$at_risk)) /
        (1 + 1.96^2 / .data$at_risk),
      half = 1.96 /
        (1 + 1.96^2 / .data$at_risk) *
        sqrt(
          .data$hazard *
            (1 - .data$hazard) /
            .data$at_risk +
            1.96^2 / (4 * .data$at_risk^2)
        ),
      lower = pmax(0, .data$centre - .data$half),
      upper = pmin(1, .data$centre + .data$half)
    ) |>
    dplyr::select(-"centre", -"half") |>
    dplyr::relocate(dplyr::all_of(by_cols), "time", "ending")
}

#' Link to a player's page on the site's Explorer
#'
#' The Players tab loads one position group at a time, so the link carries
#' the group's stat code. Offensive linemen have no stat page, so their link
#' is `NA`.
#'
#' @param player_id CFBD athlete id.
#' @param group Position group (see [position_group()]).
#' @param page The Explorer page, relative to the post.
#' @return Character vector of URLs (`NA` where the group has no page).
#' @export
explorer_player_url <- function(player_id, group, page = "explorer.html") {
  pos <- c(
    Quarterback = "QB",
    `Running back` = "RB",
    Receiver = "WR",
    `Tight end` = "TE",
    `Defensive line` = "DL",
    Linebacker = "LB",
    `Defensive back` = "DB",
    `Special teams` = "ST"
  )[group]
  dplyr::if_else(
    is.na(pos),
    NA_character_,
    sprintf("%s#tab=players&pos=%s&player=%s", page, pos, player_id)
  )
}
