# Outcomes: the person-period dependent-variable table (decision 0032). One row
# per player-season in the model population, carrying the eligibility clock and
# the drafted / NFL-entry / NFL-success labels so downstream models query the
# dependent variable directly — no further derivation at model time. NFL labels
# are outcomes only, never model inputs (leakage; decision 0014).

#' Build the person-period outcome table
#'
#' Assembles the modeling labels at the player-season grain. Given `roster`,
#' every row is one season `s` a player spends on a college roster, plus any
#' stat-line season without a roster row (decision 0050; [outcomes_backbone()]);
#' without it, the stat-line seasons in `ps_pop` alone. Each row carries
#' `has_stat_line`, the season tier of its team (given `team_season`), the
#' player's first roster season, and:
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
#' An NFL entry a year after the player's last row (a season off every
#' roster) lands on that last row, whose `draft_year` and eligibility clock
#' then describe that entry's draft, so every entrant has exactly one entry
#' row. A pick whose CFBD id is outside the
#' population links by name + college team when the match is unique. The
#' undrafted name guard skips any `gsis_id` that belongs to a draft pick and
#' any NFL debut while the player is still on a college roster (namesakes).
#' A roster-only player has no stat-line name; a pick on his id supplies one,
#' and a player with no name gets no name-guarded match.
#'
#' Rows whose outcome year is after `last_complete_draft` carry `NA` outcomes and
#' `status_end_of_season = "censored"` — administrative right-censoring, never a
#' fabricated 0.
#'
#' `hs_grad_year` comes from the name-guarded recruiting link (`hs_class`,
#' decision 0013); when unavailable it is **imputed** as the first observed
#' college season minus one (a direct HS enrollee's graduation year), taking
#' the earlier of the first roster season and the first stat season, and
#' `hs_year_imputed` is set to 1, so models can filter or flag the mis-timed
#' clock (redshirts, JUCO, late enrollees).
#'
#' @param ps_pop Stat-line population (the `ps_pop` target: player-seasons
#'   with a stat line, reused ids excluded). Must carry `playerId`, `player`,
#'   `season`; `team` enables the name + school pick fallback.
#' @param career Per-player career summary from [career_summary()] (roster
#'   backbone; used for the last observed college season).
#' @param recruiting Cleaned recruiting ratings (see [clean_recruiting()]).
#' @param picks_nfl CFBD picks bridged to nflverse ([link_nfl_draft()]).
#' @param nfl_rosters Cleaned NFL rosters (see [clean_nfl_rosters()]).
#' @param nfl_player_stats Cleaned NFL player-season stats
#'   (see [clean_nfl_player_stats()]).
#' @param nfl_draft_picks Optional nflverse draft picks
#'   (see [clean_nfl_draft_picks()]); their `gsis_id`s join the CFBD picks'
#'   as drafted players the undrafted name guard must never link.
#' @param k Fixed-horizon window (in draft classes) for
#'   `outcome_nfl_entry_by_d_plus_k`.
#' @param min_years_since_hs Required gap between HS graduation and the draft
#'   (3 for 2010-2026; stored as a column so it can vary by draft year later).
#' @param last_complete_draft Last NFL draft class with complete outcome data
#'   (default [last_complete_nfl_draft()]).
#' @param roster Optional cleaned roster ([clean_roster()]). Given, the grain
#'   is every roster player-season (decision 0050).
#' @param team_season Optional team-season table ([build_team_season()]),
#'   the source of each row's `tier`.
#'
#' @return A tibble, one row per `(playerId, season)` in
#'   [outcomes_backbone()].
#' @export
build_outcomes <- function(
  ps_pop,
  career,
  recruiting,
  picks_nfl,
  nfl_rosters,
  nfl_player_stats,
  nfl_draft_picks = NULL,
  k = 1L,
  min_years_since_hs = 3L,
  last_complete_draft = last_complete_nfl_draft(),
  roster = NULL,
  team_season = NULL
) {
  # ---- backbone: one row per (playerId, season) ------------------------------
  ps_pop <- dplyr::collect(ps_pop)
  picks_nfl <- dplyr::collect(picks_nfl)
  if (!is.null(roster)) {
    roster <- dplyr::collect(roster)
  }
  backbone <- outcomes_backbone(ps_pop, roster, career)

  # A roster-only player has no stat-line name; a pick on his id names him.
  # Rows left without a name skip every name-guarded match below.
  player_names <- dplyr::bind_rows(
    dplyr::distinct(ps_pop, .data$playerId, .data$player),
    if ("name" %in% names(picks_nfl)) {
      picks_nfl |>
        dplyr::filter(!is.na(.data$playerId), !is.na(.data$name)) |>
        dplyr::arrange(dplyr::desc(.data$year)) |>
        dplyr::transmute(.data$playerId, player = .data$name)
    }
  ) |>
    dplyr::distinct(.data$playerId, .keep_all = TRUE)
  backbone <- dplyr::left_join(backbone, player_names, by = "playerId")

  players <- backbone |>
    dplyr::group_by(.data$playerId) |>
    dplyr::summarise(
      player = dplyr::first(.data$player),
      first_row_season = min(.data$season),
      last_row_season = max(.data$season),
      first_stat_season = min_or_na(.data$season[.data$has_stat_line]),
      last_stat_season = max_or_na(.data$season[.data$has_stat_line]),
      .groups = "drop"
    ) |>
    # Roster-grain last season (may extend past the last stat season — a
    # no-stat final year still means "no further college season").
    dplyr::left_join(
      dplyr::collect(career) |>
        dplyr::select(
          "playerId",
          career_first_season = "first_season",
          career_last_season = "last_season"
        ),
      by = "playerId"
    ) |>
    dplyr::mutate(
      # A third of stat players are on a roster before their first stat line
      # (redshirts, linemen, pre-2016 defenders), so the roster dates the
      # start of college better than the stats do.
      first_season = pmin(
        .data$career_first_season,
        .data$first_row_season,
        na.rm = TRUE
      ),
      # The later of the two observations is "no further college season";
      # a backbone with stats past the roster would otherwise make the
      # censored event time collapse to 0 or less.
      last_season = pmax(
        .data$career_last_season,
        .data$last_row_season,
        na.rm = TRUE
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
      hs_matched = (!is.na(.data$recruit_name) &
        normalize_name(.data$player) == normalize_name(.data$recruit_name)) %in%
        TRUE,
      hs_class_matched = dplyr::if_else(
        .data$hs_matched,
        .data$hs_class,
        NA_integer_
      ),
      hs_year_imputed = is.na(.data$hs_class_matched),
      hs_grad_year = dplyr::coalesce(
        .data$hs_class_matched,
        .data$first_season - 1L
      )
    ) |>
    dplyr::select(
      "playerId",
      "hs_grad_year",
      "hs_year_imputed",
      "last_season",
      first_roster_season = "career_first_season"
    )

  backbone <- backbone |>
    dplyr::group_by(.data$playerId) |>
    dplyr::mutate(
      next_season = dplyr::lead(.data$season),
      is_last_row = .data$season == max(.data$season)
    ) |>
    dplyr::ungroup() |>
    dplyr::left_join(hs, by = "playerId") |>
    dplyr::mutate(
      draft_year = .data$season + 1L,
      is_first_roster_season = (.data$season == .data$first_roster_season) %in%
        TRUE
    )

  # ---- season-aware tier from the row's team (decision 0003) -----------------
  if (!is.null(team_season)) {
    row_team <- dplyr::bind_rows(
      if ("team" %in% names(ps_pop)) {
        dplyr::distinct(ps_pop, .data$playerId, .data$season, .data$team)
      },
      if (!is.null(roster)) {
        dplyr::distinct(roster, .data$playerId, .data$season, .data$team)
      }
    ) |>
      dplyr::filter(!is.na(.data$team)) |>
      # The stat-line team first; a mid-season second team is dropped.
      dplyr::distinct(.data$playerId, .data$season, .keep_all = TRUE)
    backbone <- backbone |>
      dplyr::left_join(row_team, by = c("playerId", "season")) |>
      dplyr::left_join(
        dplyr::collect(team_season) |>
          dplyr::select("team", "season", "tier", "tier_label"),
        by = c("team", "season")
      )
  }

  # ---- drafted labels (decision 0011: one pick per player, draft window) -----
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
    # year at or before the player's first college season is impossible for a
    # real career, so the whole link is nulled rather than trusted.
    dplyr::left_join(
      dplyr::select(players, "playerId", "first_season", "last_season"),
      by = "playerId"
    ) |>
    # The same entry window as the UDFA match: a pick years after the last
    # college season is another person on a recycled id, not a late entry.
    dplyr::filter(
      .data$pick_draft_year > .data$first_season,
      .data$pick_draft_year <= .data$last_season + 2L
    ) |>
    dplyr::select(-"first_season", -"last_season")

  # A pick whose CFBD id is not in the population (the pick and the stat line
  # carry different ids, e.g. Zay Jones) links by name + college team, only
  # when exactly one player and one pick match, within the entry window.
  pop_teams <- if ("team" %in% names(ps_pop) || !is.null(roster)) {
    dplyr::bind_rows(
      if ("team" %in% names(ps_pop)) dplyr::select(ps_pop, "playerId", "team"),
      if (!is.null(roster)) dplyr::select(roster, "playerId", "team")
    ) |>
      dplyr::distinct(.data$playerId, .data$team)
  }
  if (!is.null(pop_teams)) {
    # Fail loudly rather than quietly dropping the recovered picks.
    stopifnot(all(c("name", "collegeTeam") %in% names(picks_nfl)))
    fallback <- picks_nfl |>
      dplyr::filter(
        .data$year %in% 2010:2027,
        is.na(.data$playerId) | !.data$playerId %in% players$playerId
      ) |>
      dplyr::transmute(
        pick_key = dplyr::row_number(),
        norm = normalize_name(.data$name),
        team = .data$collegeTeam,
        pick_draft_year = as.integer(.data$year),
        pick_round = as.integer(.data$round),
        pick_overall = as.integer(.data$overall),
        .data$gsis_id
      ) |>
      dplyr::inner_join(
        players |>
          dplyr::filter(
            !.data$playerId %in% pick_lookup$playerId,
            !is.na(.data$player)
          ) |>
          dplyr::transmute(
            .data$playerId,
            norm = normalize_name(.data$player),
            .data$first_season,
            .data$last_season
          ) |>
          dplyr::inner_join(pop_teams, by = "playerId"),
        by = c("norm", "team"),
        relationship = "many-to-many"
      ) |>
      dplyr::filter(
        .data$pick_draft_year > .data$first_season,
        .data$pick_draft_year <= .data$last_season + 2L
      ) |>
      dplyr::distinct(.data$pick_key, .data$playerId, .keep_all = TRUE) |>
      dplyr::filter(dplyr::n() == 1L, .by = "pick_key") |>
      dplyr::filter(dplyr::n() == 1L, .by = "playerId") |>
      dplyr::select(dplyr::all_of(names(pick_lookup)))
    pick_lookup <- dplyr::bind_rows(pick_lookup, fallback)
  }
  # Any gsis that belongs to a draft pick is a drafted player, never a UDFA.
  drafted_gsis <- unique(stats::na.omit(c(
    picks_nfl$gsis_id,
    if (!is.null(nfl_draft_picks)) dplyr::collect(nfl_draft_picks)$gsis_id
  )))

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
    dplyr::filter(
      !.data$playerId %in% pick_lookup$playerId,
      !is.na(.data$player)
    ) |>
    dplyr::transmute(
      .data$playerId,
      norm = normalize_name(.data$player),
      # The same person cannot debut in the NFL while still on a college
      # roster: an earlier first NFL season is a namesake.
      entry_lo = .data$last_season + 1L,
      entry_hi = .data$last_season + 2L
    ) |>
    dplyr::inner_join(
      dplyr::mutate(
        dplyr::filter(rosters, !.data$gsis_id %in% drafted_gsis),
        norm = normalize_name(.data$player_name)
      ) |>
        dplyr::select("norm", "gsis_id"),
      by = "norm",
      # Name candidates fan out both ways (shared names); the summarise below
      # keeps only players with exactly one candidate.
      relationship = "many-to-many"
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
      # The year this row's outcome is decided: the next draft, except on a
      # player's last row, where a later entry (after seasons off every
      # roster) is the outcome that follows it.
      event_year = dplyr::if_else(
        .data$is_last_row &
          !is.na(.data$entry_year) &
          .data$entry_year > .data$draft_year,
        .data$entry_year,
        .data$draft_year
      ),
      # The row's draft and its eligibility clock describe that same draft.
      draft_year = .data$event_year,
      years_since_hs = .data$draft_year - .data$hs_grad_year,
      min_years_since_hs = as.integer(.env$min_years_since_hs),
      draft_eligible = .data$years_since_hs >= .data$min_years_since_hs,
      outcome_observed_d = .data$event_year <= .env$last_complete_draft,
      outcome_drafted_d = dplyr::if_else(
        .data$outcome_observed_d,
        !is.na(.data$pick_draft_year) &
          .data$pick_draft_year == .data$event_year,
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
          .data$event_year == .data$nfl_first_season,
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
          .data$entry_year <= .data$event_year + as.integer(.env$k) - 1L,
        NA
      )
    ) |>
    dplyr::left_join(
      roster_seasons,
      by = c("gsis_id", "event_year" = "season")
    ) |>
    dplyr::left_join(
      games_lookup,
      by = c("gsis_id", "event_year" = "season")
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
      eligible_season_index = dplyr::if_else(
        .data$draft_eligible,
        cumsum(.data$draft_eligible),
        NA_integer_
      ),
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
        "career_first_season",
        "career_last_season",
        "first_season",
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
        "first_eligible_season",
        "is_last_row",
        "first_row_season",
        "last_row_season",
        "event_year"
      ))
    )

  out <- out |>
    dplyr::relocate(
      dplyr::any_of(c(
        "playerId",
        "player",
        "season",
        "has_stat_line",
        "team",
        "tier",
        "tier_label",
        "first_roster_season",
        "is_first_roster_season",
        "hs_grad_year",
        "hs_year_imputed",
        "last_season",
        "draft_year",
        "years_since_hs",
        "min_years_since_hs",
        "draft_eligible",
        "eligible_season_index"
      ))
    )

  # No silent fan-out: the outcome join must preserve the population grain.
  stopifnot(
    nrow(out) == nrow(backbone),
    !any(duplicated(out[c("playerId", "season")]))
  )
  out
}

#' Player-seasons in the outcome population
#'
#' The `(playerId, season)` grain of [build_outcomes()]: every stat-line
#' player-season in `ps_pop`, plus, given `roster`, every roster player-season
#' of a player in `career` (which already excludes recycled ids, decision
#' 0022). `has_stat_line` marks the seasons from `ps_pop`.
#'
#' @param ps_pop Stat-line population (the `ps_pop` target).
#' @param roster Optional cleaned roster ([clean_roster()]); `NULL` keeps the
#'   stat-line population alone.
#' @param career Career summary ([career_summary()]); required with `roster`.
#'
#' @return A tibble of `playerId`, `season`, `has_stat_line`, one row per
#'   player-season, sorted.
#' @export
outcomes_backbone <- function(ps_pop, roster = NULL, career = NULL) {
  stat <- dplyr::collect(ps_pop) |>
    dplyr::distinct(.data$playerId, .data$season) |>
    dplyr::mutate(has_stat_line = TRUE)
  if (!is.null(roster)) {
    stopifnot(!is.null(career))
    on_roster <- dplyr::collect(roster) |>
      dplyr::filter(.data$playerId %in% dplyr::collect(career)$playerId) |>
      dplyr::distinct(.data$playerId, .data$season)
    stat <- dplyr::full_join(stat, on_roster, by = c("playerId", "season")) |>
      dplyr::mutate(has_stat_line = dplyr::coalesce(.data$has_stat_line, FALSE))
  }
  dplyr::arrange(stat, .data$playerId, .data$season)
}

min_or_na <- function(x) if (length(x)) min(x) else NA_integer_
max_or_na <- function(x) if (length(x)) max(x) else NA_integer_
