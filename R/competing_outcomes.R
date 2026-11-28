# Competing endings of a college career (feature F24): each draft-eligible
# player's career ends once, in one of three ways, on an eligible-season clock.
# A final season off every roster resolves to exhausted_undrafted in
# build_outcomes(), so the left_data label is kept only as a guard.
# Built on the fly from `outcomes` (decision 0041); NFL labels stay outcomes.

#' Reader-facing labels for the career endings
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
#' @return A tibble: the `by` column, `time` (0 to the last season with
#'   players at risk), `state` (an [ending_labels()] code or `"playing"`),
#'   `estimate`, `lower`, `upper` and `n_risk` (players still playing going
#'   into that season, the same on every state's row).
#' @export
ending_incidence <- function(endings, by = "group") {
  rlang::check_installed(
    "survival",
    reason = "for the Aalen-Johansen estimate."
  )
  states <- names(ending_labels())
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

#' Discrete-time competing-risks model of the career endings
#'
#' Expands [career_endings()] into one row per player per eligible season
#' still playing, whose outcome is the ending in that season or `"playing"`
#' (played on, or censored after it), and fits a multinomial logit
#' ([nnet::multinom()]) with `"playing"` as the reference. With one term per
#' eligible season and no covariate the fitted chances are the per-season
#' hazards of [ending_hazards()] and they compound into the Aalen-Johansen
#' shares of [ending_incidence()]; with a single intercept each ending has one
#' chance for every season. A `by` covariate adds one main effect per group,
#' the same shift in each ending's log odds in every season.
#'
#' @inheritParams ending_incidence
#' @param season_terms Fit one term per eligible season (`TRUE`) or a single
#'   intercept per ending (`FALSE`).
#' @param by Covariate column added as a main effect, or `NULL` for none.
#' @return A tibble: the `by` column, `time`, `state` (an ending code or
#'   `"playing"`), `chance` (fitted share of players still playing going into
#'   `time` who end that way in it), `cumulative` (share of all players whose
#'   career has ended that way by `time`; for `"playing"`, still playing after
#'   it) and `n_risk`. The fit is attached as the `"fit"` attribute.
#' @export
ending_multinom <- function(endings, season_terms = TRUE, by = NULL) {
  rlang::check_installed("nnet", reason = "for the multinomial model.")
  endings <- dplyr::filter(endings, .data$time > 0L)
  if (!is.null(by)) {
    endings[[by]] <- droplevels(as.factor(endings[[by]]))
  }
  times <- seq_len(max(endings$time))
  present <- intersect(names(ending_labels()), unique(endings$ending))
  # Person-period rows, aggregated to counts per season, group and outcome.
  pp <- purrr::map(times, \(t) {
    endings |>
      dplyr::filter(.data$time >= t) |>
      dplyr::mutate(
        y = dplyr::if_else(
          .data$time == t & .data$ending != "censored",
          .data$ending,
          "playing"
        )
      ) |>
      dplyr::count(dplyr::across(dplyr::all_of(c(by, "y")))) |>
      dplyr::mutate(time = t)
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(
      y = factor(.data$y, c("playing", present)),
      season = factor(.data$time, levels = times)
    )
  terms <- c(if (season_terms) "season", by)
  form <- stats::reformulate(if (length(terms)) terms else "1", response = "y")
  fit <- nnet::multinom(
    form,
    data = pp,
    weights = n,
    trace = FALSE,
    maxit = 1000,
    reltol = 1e-12
  )
  groups <- if (is.null(by)) list(NULL) else as.list(levels(endings[[by]]))
  out <- purrr::map(groups, function(g) {
    newdata <- data.frame(season = factor(times, levels = times))
    d <- endings
    if (!is.null(by)) {
      newdata[[by]] <- factor(g, levels = levels(endings[[by]]))
      d <- endings[endings[[by]] == g, ]
    }
    p <- stats::predict(fit, newdata = newdata, type = "probs")
    p <- matrix(p, nrow = length(times), dimnames = list(NULL, levels(pp$y)))
    # Each season's endings apply to the share still playing going into it.
    surv_before <- c(1, cumprod(p[, "playing"]))[times]
    cumulative <- apply(p[, present, drop = FALSE] * surv_before, 2, cumsum)
    cumulative <- matrix(cumulative, nrow = length(times))
    cumulative <- cbind(cumulative, cumprod(p[, "playing"]))
    colnames(cumulative) <- c(present, "playing")
    n_risk <- vapply(times, \(t) sum(d$time >= t), integer(1))
    long <- function(m, nm) {
      tibble::as_tibble(m[, c(present, "playing"), drop = FALSE]) |>
        dplyr::mutate(time = times) |>
        tidyr::pivot_longer(-"time", names_to = "state", values_to = nm)
    }
    res <- long(p, "chance") |>
      dplyr::left_join(
        long(cumulative, "cumulative"),
        by = c("time", "state")
      ) |>
      dplyr::left_join(
        tibble::tibble(time = times, n_risk = n_risk),
        by = "time"
      )
    if (!is.null(by)) {
      res[[by]] <- g
      res <- dplyr::relocate(res, dplyr::all_of(by))
    }
    res
  }) |>
    purrr::list_rbind()
  attr(out, "fit") <- fit
  out
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
