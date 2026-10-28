# Outcomes: the person-period dependent-variable table (decision 0032). One row
# per player-season in the model population, carrying the eligibility clock and
# the drafted / NFL-entry / NFL-success labels so downstream models query the
# dependent variable directly — no further derivation at model time. NFL labels
# are outcomes only, never model inputs (leakage; decision 0014).

#' Build the person-period outcome table
#'
#' Assembles the modeling labels at the player-season grain. Every row is one
#' observed stat season `s` for a player in the model population, with:
#'
#' - an **eligibility clock** anchored at high-school graduation `h`
#'   (`hs_grad_year`): the draft following `s` is `d = s + 1`, the player is
#'   draft-eligible when `d - h >= min_years_since_hs` (3 for 2010-2026);
#' - **drafted** labels for draft `d` (event flag, round, overall pick, round
#'   group) from the one-pick-per-player lookup (decision 0011);
#' - **NFL entry** labels: `outcome_signed_udfa_d` (name-guarded match against
#'   NFL rosters for undrafted players, decision 0013/0014) and the combined
#'   `outcome_nfl_entry_d` / type / fixed-horizon flag;
#' - **NFL success** labels: made the regular-season roster and rookie games in
#'   the entry year;
#' - **survival bookkeeping**: event time, event indicator, end-of-season
#'   status, and administrative right-censoring (`outcome_observed_d`).
#'
#' Rows whose draft `d` is after `last_complete_draft` carry `NA` outcomes and
#' `status_end_of_season = "censored"` — administrative right-censoring, never a
#' fabricated 0.
#'
#' `hs_grad_year` comes from the name-guarded recruiting link (`hs_class`,
#' decision 0013); when unavailable it is **imputed** as the first observed
#' college season minus one (a direct HS enrollee's graduation year) and
#' `hs_year_imputed` is set to 1, so models can filter or flag the mis-timed
#' clock (redshirts, JUCO, late enrollees).
#'
#' @param ps_pop Model population (the `ps_pop` target: player-seasons with a
#'   stat line, reused ids excluded). Must carry `playerId`, `player`, `season`.
#' @param career Per-player career summary from [career_summary()] (roster
#'   backbone; used for the last observed college season).
#' @param recruiting Cleaned recruiting ratings (see [clean_recruiting()]).
#' @param picks_nfl CFBD picks bridged to nflverse ([link_nfl_draft()]).
#' @param nfl_rosters Cleaned NFL rosters (see [clean_nfl_rosters()]).
#' @param nfl_player_stats Cleaned NFL player-season stats
#'   (see [clean_nfl_player_stats()]).
#' @param k Fixed-horizon window (in draft classes) for
#'   `outcome_nfl_entry_by_d_plus_k`.
#' @param min_years_since_hs Required gap between HS graduation and the draft
#'   (3 for 2010-2026; stored as a column so it can vary by draft year later).
#' @param last_complete_draft Last NFL draft class with complete outcome data
#'   (default [last_complete_nfl_draft()]).
#'
#' @return A tibble, one row per `(playerId, season)` in `ps_pop`.
#' @export
build_outcomes <- function(
  ps_pop,
  career,
  recruiting,
  picks_nfl,
  nfl_rosters,
  nfl_player_stats,
  k = 1L,
  min_years_since_hs = 3L,
  last_complete_draft = last_complete_nfl_draft()
) {
  # ---- backbone: one row per (playerId, season) ------------------------------
  backbone <- dplyr::collect(ps_pop) |>
    dplyr::distinct(.data$playerId, .data$player, .data$season) |>
    dplyr::arrange(.data$playerId, .data$season)

  players <- backbone |>
    dplyr::group_by(.data$playerId) |>
    dplyr::summarise(
      player = dplyr::first(.data$player),
      first_stat_season = min(.data$season),
      last_stat_season = max(.data$season),
      .groups = "drop"
    ) |>
    # Roster-grain last season (may extend past the last stat season — a
    # no-stat final year still means "no further college season").
    dplyr::left_join(
      dplyr::collect(career) |>
        dplyr::select("playerId", career_last_season = "last_season"),
      by = "playerId"
    ) |>
    dplyr::mutate(
      # The later of the two observations is "no further college season";
      # a backbone with stats past the roster would otherwise make the
      # censored event time collapse to 0 or less.
      last_season = pmax(
        dplyr::coalesce(.data$career_last_season, .data$last_stat_season),
        .data$last_stat_season
      )
    )

  # ---- eligibility clock ------------------------------------------------------
  # HS graduation year: name-guarded recruiting hs_class, else imputed.
  hs <- players |>
    dplyr::left_join(
      dplyr::select(
        recruiting,
        "playerId",
        recruit_name = "recruit_name",
        "hs_class"
      ),
      by = "playerId"
    ) |>
    dplyr::mutate(
      hs_matched = !is.na(.data$recruit_name) &
        normalize_name(.data$player) == normalize_name(.data$recruit_name),
      hs_class_matched = dplyr::if_else(
        .data$hs_matched,
        .data$hs_class,
        NA_integer_
      ),
      hs_year_imputed = is.na(.data$hs_class_matched),
      hs_grad_year = dplyr::coalesce(
        .data$hs_class_matched,
        .data$first_stat_season - 1L
      )
    ) |>
    dplyr::select(
      "playerId",
      "hs_grad_year",
      "hs_year_imputed",
      "last_season"
    )

  backbone <- backbone |>
    dplyr::group_by(.data$playerId) |>
    dplyr::mutate(next_season = dplyr::lead(.data$season)) |>
    dplyr::ungroup() |>
    dplyr::left_join(hs, by = "playerId") |>
    dplyr::mutate(
      draft_year = .data$season + 1L,
      years_since_hs = .data$draft_year - .data$hs_grad_year,
      min_years_since_hs = as.integer(.env$min_years_since_hs),
      draft_eligible = .data$years_since_hs >= .data$min_years_since_hs
    ) |>
    dplyr::group_by(.data$playerId) |>
    dplyr::mutate(
      eligible_season_index = dplyr::if_else(
        .data$draft_eligible,
        cumsum(.data$draft_eligible),
        NA_integer_
      )
    ) |>
    dplyr::ungroup()

  # ---- drafted labels (decision 0011: one pick per player, draft window) -----
  picks_nfl <- dplyr::collect(picks_nfl)
  pick_lookup <- picks_nfl |>
    dplyr::filter(!is.na(.data$playerId), .data$year %in% 2010:2027) |>
    dplyr::arrange(.data$playerId, dplyr::desc(.data$year)) |>
    dplyr::distinct(.data$playerId, .keep_all = TRUE) |>
    dplyr::transmute(
      .data$playerId,
      pick_draft_year = as.integer(.data$year),
      pick_round = as.integer(.data$round),
      pick_overall = as.integer(.data$overall),
      gsis_id
    ) |>
    # CFBD id reuse can surface an era-collision pick (decision 0011): a draft
    # year at or before the player's first stat season is impossible for a real
    # career, so the whole link is nulled rather than trusted.
    dplyr::left_join(
      dplyr::select(players, "playerId", "first_stat_season"),
      by = "playerId"
    ) |>
    dplyr::filter(.data$pick_draft_year > .data$first_stat_season) |>
    dplyr::select(-"first_stat_season")

  # ---- UDFA entry: name-guarded roster match for undrafted players ----------
  # No draft slot to key on, so the match is by normalized name; an ambiguous
  # name (multiple candidate gsis_ids) resolves to no link rather than a guess
  # (decision 0014). Candidates are bounded to plausible entry windows.
  rosters <- nfl_rosters |>
    dplyr::distinct(.data$gsis_id, .data$player_name) |>
    dplyr::collect()
  gsis_first <- nfl_rosters |>
    dplyr::distinct(.data$gsis_id, .data$season) |>
    dplyr::collect() |>
    dplyr::filter(!is.na(.data$gsis_id)) |>
    dplyr::group_by(.data$gsis_id) |>
    dplyr::summarise(nfl_first_season = min(.data$season), .groups = "drop")

  udfa_map <- players |>
    dplyr::transmute(
      .data$playerId,
      norm = normalize_name(.data$player),
      entry_lo = .data$first_stat_season + 1L,
      entry_hi = .data$last_season + 2L
    ) |>
    dplyr::inner_join(
      dplyr::mutate(
        rosters,
        norm = normalize_name(.data$player_name)
      ) |>
        dplyr::select("norm", "gsis_id"),
      by = "norm"
    ) |>
    dplyr::left_join(gsis_first, by = "gsis_id") |>
    # Bound candidates to a plausible entry window by their actual first NFL
    # season (rookie_year is NA for some long-tenured players, so it cannot be
    # the gate — same-name veterans would slip through and poison the labels).
    dplyr::filter(
      .data$nfl_first_season >= .data$entry_lo &
        .data$nfl_first_season <= .data$entry_hi
    ) |>
    dplyr::group_by(.data$playerId) |>
    dplyr::summarise(
      n_candidates = dplyr::n_distinct(.data$gsis_id),
      udfa_gsis = dplyr::first(.data$gsis_id),
      .groups = "drop"
    ) |>
    dplyr::filter(.data$n_candidates == 1L) |>
    dplyr::select("playerId", "udfa_gsis") |>
    dplyr::left_join(gsis_first, by = c("udfa_gsis" = "gsis_id"))

  # ---- NFL success lookups: roster presence and games by (gsis, season) -----
  roster_seasons <- nfl_rosters |>
    dplyr::distinct(.data$gsis_id, .data$season) |>
    dplyr::collect() |>
    dplyr::filter(!is.na(.data$gsis_id)) |>
    dplyr::mutate(on_roster = TRUE)
  games_lookup <- nfl_player_stats |>
    dplyr::select("gsis_id", "season", "games") |>
    dplyr::collect() |>
    dplyr::filter(!is.na(.data$gsis_id)) |>
    dplyr::group_by(.data$gsis_id, .data$season) |>
    dplyr::summarise(
      entry_games = sum(.data$games, na.rm = TRUE),
      .groups = "drop"
    )

  # ---- assemble the person-period outcomes -----------------------------------
  out <- backbone |>
    dplyr::left_join(pick_lookup, by = "playerId") |>
    dplyr::left_join(udfa_map, by = "playerId") |>
    dplyr::mutate(
      gsis_id = dplyr::coalesce(.data$gsis_id, .data$udfa_gsis),
      entry_year = dplyr::coalesce(
        .data$pick_draft_year,
        .data$nfl_first_season
      ),
      outcome_observed_d = .data$draft_year <= .env$last_complete_draft,
      outcome_drafted_d = dplyr::if_else(
        .data$outcome_observed_d,
        !is.na(.data$pick_draft_year) &
          .data$pick_draft_year == .data$draft_year,
        NA
      ),
      outcome_draft_round_d = dplyr::if_else(
        .data$outcome_drafted_d %in% TRUE,
        .data$pick_round,
        NA_integer_
      ),
      outcome_draft_pick_d = dplyr::if_else(
        .data$outcome_drafted_d %in% TRUE,
        .data$pick_overall,
        NA_integer_
      ),
      outcome_draft_round_group_d = dplyr::case_when(
        !.data$outcome_observed_d ~ NA_character_,
        .data$outcome_drafted_d %in% TRUE & .data$pick_round == 1L ~ "r1",
        .data$outcome_drafted_d %in% TRUE & .data$pick_round <= 3L ~ "r2_3",
        .data$outcome_drafted_d %in% TRUE ~ "r4_7",
        TRUE ~ "undrafted"
      ),
      # FALSE (not NA) for observed undrafted players with no roster match —
      # only censored rows carry NA (dict: "else 0 (NA when censored)"). A
      # drafted player is FALSE here by mutual exclusivity, even when the pick
      # year differs from this row's draft year.
      outcome_signed_udfa_d = dplyr::case_when(
        !.data$outcome_observed_d ~ NA,
        .data$outcome_drafted_d %in% TRUE ~ FALSE,
        !is.na(.data$nfl_first_season) ~
          .data$draft_year == .data$nfl_first_season,
        TRUE ~ FALSE
      ),
      outcome_nfl_entry_d = dplyr::if_else(
        .data$outcome_observed_d,
        dplyr::coalesce(.data$outcome_drafted_d, FALSE) |
          dplyr::coalesce(.data$outcome_signed_udfa_d, FALSE),
        NA
      ),
      outcome_nfl_entry_type_d = dplyr::case_when(
        !.data$outcome_observed_d ~ NA_character_,
        .data$outcome_drafted_d %in% TRUE ~ paste0(
          "drafted_",
          dplyr::case_when(
            .data$pick_round == 1L ~ "r1",
            .data$pick_round <= 3L ~ "r2_3",
            TRUE ~ "r4_7"
          )
        ),
        .data$outcome_signed_udfa_d %in% TRUE ~ "udfa",
        TRUE ~ "none"
      ),
      outcome_nfl_entry_by_d_plus_k = dplyr::if_else(
        .data$outcome_observed_d,
        !is.na(.data$entry_year) &
          .data$entry_year <= .data$draft_year + as.integer(.env$k) - 1L,
        NA
      )
    ) |>
    dplyr::left_join(
      roster_seasons,
      by = c("gsis_id", "draft_year" = "season")
    ) |>
    dplyr::left_join(
      games_lookup,
      by = c("gsis_id", "draft_year" = "season")
    ) |>
    dplyr::mutate(
      outcome_made_roster_entry_year = dplyr::if_else(
        .data$outcome_nfl_entry_d %in% TRUE,
        dplyr::coalesce(.data$on_roster, FALSE),
        NA
      ),
      outcome_rookie_games_entry_year = dplyr::if_else(
        .data$outcome_nfl_entry_d %in% TRUE,
        as.integer(dplyr::coalesce(.data$entry_games, 0)),
        NA_integer_
      ),
      outcome_source = dplyr::case_when(
        .data$outcome_drafted_d %in% TRUE ~ "draft_table",
        .data$outcome_signed_udfa_d %in%
          TRUE |
          .data$outcome_made_roster_entry_year %in% TRUE ~ "roster_table",
        TRUE ~ "none"
      )
    )

  # ---- survival bookkeeping (player-level constants) -------------------------
  out <- out |>
    dplyr::group_by(.data$playerId) |>
    dplyr::mutate(
      first_eligible_season = dplyr::first(.data$season[.data$draft_eligible]),
      # Event time in years since HS: entry draft year for entrants (even when
      # the eligibility clock says they were never eligible — an early entrant
      # or an imputed-HS mis-timing — the positivity contract flags nonsense),
      # else the last observed draft year (right-censored).
      years_to_nfl_entry = dplyr::if_else(
        !is.na(.data$entry_year),
        .data$entry_year - .data$hs_grad_year,
        (.data$last_season + 1L) - .data$hs_grad_year
      ),
      nfl_entry_event = !is.na(.data$entry_year),
      exhausted = .data$season == .data$last_season,
      status_end_of_season = dplyr::case_when(
        !.data$outcome_observed_d ~ "censored",
        .data$outcome_drafted_d %in% TRUE ~ "drafted",
        .data$outcome_signed_udfa_d %in% TRUE ~ "signed_udfa",
        .data$exhausted ~ "exhausted_undrafted",
        .data$next_season == .data$season + 1L ~ "continuing",
        TRUE ~ "left_data"
      )
    ) |>
    dplyr::ungroup() |>
    dplyr::select(
      -dplyr::any_of(c(
        "next_season",
        "career_last_season",
        "last_stat_season",
        "first_stat_season",
        "recruit_name",
        "hs_class",
        "hs_matched",
        "hs_class_matched",
        "pick_draft_year",
        "pick_round",
        "pick_overall",
        "udfa_gsis",
        "nfl_first_season",
        "n_candidates",
        "entry_year",
        "entry_games",
        "on_roster",
        "exhausted",
        "first_eligible_season"
      ))
    )

  # No silent fan-out: the outcome join must preserve the population grain.
  stopifnot(
    nrow(out) ==
      nrow(dplyr::distinct(
        dplyr::collect(ps_pop),
        .data$playerId,
        .data$season
      )),
    !any(duplicated(out[c("playerId", "season")]))
  )
  out
}
