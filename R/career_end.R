# Career endings: how each college career stopped (issue #51, part 1). A derived
# table at the career grain, built on `career_summary()` and `outcomes`. The
# early-stop category is a PROXY for an injury-shaped exit: CFBD has no injury
# feed, so a career that stops with eligibility left is labelled by absence
# alone (decision 0039).

#' Reader-facing career-ending categories, in precedence order
#'
#' The values [career_end_status()] can assign. Mutually exclusive and
#' exhaustive: every career gets exactly one. Names are the stored codes; values
#' are the reader-facing labels.
#'
#' @noRd
career_end_levels <- c(
  right_censored = "Still active, or the next draft is not yet observed",
  not_in_model_population = "No stat line; undrafted NFL status not resolved",
  drafted = "Drafted",
  signed_udfa = "Signed as an undrafted free agent",
  eligibility_exhausted = "Eligibility used up, no NFL entry",
  eligibility_unknown = "Stopped; the eligibility clock starts before the data",
  transferred_then_stopped = "Changed schools, then stopped with eligibility left",
  early_stop = "Stopped with eligibility left (injury-shaped proxy)"
)

#' Classify how each college career ended
#'
#' One row per career from [career_summary()], with a single `career_end`
#' category. This is a **proxy**: an early stop is a career that ended while
#' eligibility remained, with no NFL entry and no transfer, and is only
#' *injury-shaped*. Injury, academics, a walk-on quitting, and a
#' transfer to a school outside the roster data all look the same from
#' absence alone. CFBD has no injury feed (decision 0039).
#'
#' Rules, applied in this order (first match wins):
#'
#' 1. `right_censored`: the career is not yet observed to end. Either its last
#'    roster season is the latest season in the data, or the NFL draft that
#'    follows it is past `last_complete_draft` (decision 0032). Censored careers
#'    are never early stops.
#' 2. `drafted`: a CFBD pick bridged to the career (any career, stat line or not).
#' 3. `signed_udfa`: an undrafted player matched to an NFL roster by the name
#'    guard (decision 0014). Only players in the model population carry this.
#' 4. `not_in_model_population`: no stat line and not drafted, so [build_outcomes()]
#'    holds no UDFA label for the career. Its undrafted-NFL status is unknown
#'    here, not "none".
#' 5. `eligibility_exhausted`: the eligibility clock is used up (see below).
#' 6. `eligibility_unknown`: eligibility remains, but the clock may have started
#'    before the first roster season (the data begins in 2010), so the time left
#'    is not measurable.
#' 7. `transferred_then_stopped`: eligibility remains, and the player was on more
#'    than one roster team. A school change makes the exit ambiguous.
#' 8. `early_stop`: eligibility remains, a single school, no NFL entry. This is
#'    the proxy.
#'
#' **Eligibility clock.** Calendar seasons from the first roster season through
#' the last, minus the 2020 season (NCAA's COVID-19 waiver did not count it),
#' compared against `eligibility_seasons` (5). Medical hardship waivers and
#' redshirt-year rules are not observable, so "exhausted" can be wrong for an
#' athlete who received one.
#'
#' @param career Per-player career summary (see [career_summary()]): `playerId`,
#'   `first_season`, `last_season`, `seasons`, `transfers`, `gap_seasons`.
#' @param outcomes Person-period outcome table (see [build_outcomes()]):
#'   `playerId`, `outcome_signed_udfa_d`. Players absent from it are outside the
#'   model population and have no UDFA label.
#' @param picks_nfl CFBD picks bridged to nflverse (see [link_nfl_draft()]):
#'   `playerId`, `year`. Source of the drafted label for every career.
#' @param eligibility_seasons Seasons of NCAA eligibility (5).
#' @param covid_season Season not counted against eligibility (2020).
#' @param last_complete_draft Last NFL draft class with complete outcome data
#'   (default [last_complete_nfl_draft()]).
#'
#' @return One row per `playerId` with `seasons`, `first_season`, `last_season`,
#'   `transfers`, `gap_seasons`, `clock_seasons_used`, `eligibility_remaining`,
#'   `clock_start_observed`, `in_model_population`, `drafted`, `signed_udfa`,
#'   `right_censored`, `career_end` (see `career_end_levels`), and
#'   `early_stop_proxy` (TRUE only for `career_end == "early_stop"`).
#' @export
career_end_status <- function(
  career,
  outcomes,
  picks_nfl,
  eligibility_seasons = 5L,
  covid_season = 2020L,
  last_complete_draft = last_complete_nfl_draft()
) {
  data_start <- min(career$first_season)
  last_roster_season <- max(career$last_season)

  # Drafted comes from the CFBD picks bridge for EVERY career, not from
  # `outcomes`, which only covers the stat-line population: a drafted walk-on
  # would otherwise read as an early stop. Same rule as build_outcomes(): one
  # pick per player, draft window, and a draft after the first roster season
  # (drops CFBD id-reuse collisions, decision 0011).
  drafted_ids <- picks_nfl |>
    dplyr::filter(
      !is.na(.data$playerId),
      .data$year %in% 2010:2027
    ) |>
    dplyr::distinct(.data$playerId, .data$year) |>
    dplyr::inner_join(
      dplyr::select(career, "playerId", "first_season"),
      by = "playerId"
    ) |>
    dplyr::filter(.data$year > .data$first_season) |>
    dplyr::distinct(.data$playerId) |>
    dplyr::mutate(drafted = TRUE)

  # UDFA: name-guarded roster match from `outcomes` (decision 0014). Only
  # players in the model population have it.
  udfa_ids <- outcomes |>
    dplyr::filter(.data$outcome_signed_udfa_d %in% TRUE) |>
    dplyr::distinct(.data$playerId) |>
    dplyr::mutate(udfa_match = TRUE)

  nfl <- dplyr::full_join(drafted_ids, udfa_ids, by = "playerId") |>
    dplyr::mutate(
      drafted = dplyr::coalesce(.data$drafted, FALSE),
      # Drafted wins: a same-name roster match cannot also make the player an
      # undrafted signee, keeping the categories mutually exclusive.
      signed_udfa = dplyr::coalesce(.data$udfa_match, FALSE) & !.data$drafted
    ) |>
    dplyr::select("playerId", "drafted", "signed_udfa")

  career |>
    dplyr::left_join(nfl, by = "playerId") |>
    dplyr::mutate(
      in_model_population = .data$playerId %in% outcomes$playerId,
      drafted = dplyr::coalesce(.data$drafted, FALSE),
      signed_udfa = dplyr::coalesce(.data$signed_udfa, FALSE),
      clock_seasons_used = .data$last_season -
        .data$first_season +
        1L -
        as.integer(
          .data$first_season <= covid_season & .data$last_season >= covid_season
        ),
      eligibility_remaining = as.integer(eligibility_seasons) -
        .data$clock_seasons_used,
      clock_start_observed = .data$first_season > data_start,
      right_censored = .data$last_season >= last_roster_season |
        .data$last_season + 1L > last_complete_draft,
      career_end = dplyr::case_when(
        .data$right_censored ~ "right_censored",
        .data$drafted ~ "drafted",
        .data$signed_udfa ~ "signed_udfa",
        !.data$in_model_population ~ "not_in_model_population",
        .data$eligibility_remaining <= 0L ~ "eligibility_exhausted",
        !.data$clock_start_observed ~ "eligibility_unknown",
        .data$transfers > 0L ~ "transferred_then_stopped",
        TRUE ~ "early_stop"
      ),
      early_stop_proxy = .data$career_end == "early_stop"
    ) |>
    dplyr::select(
      "playerId",
      "first_season",
      "last_season",
      "seasons",
      "transfers",
      "gap_seasons",
      "clock_seasons_used",
      "eligibility_remaining",
      "clock_start_observed",
      "in_model_population",
      "drafted",
      "signed_udfa",
      "right_censored",
      "career_end",
      "early_stop_proxy"
    )
}
