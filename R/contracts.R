# Data contracts (decision 0005 / VISION §8). pointblank agents that assert the
# schema, key integrity, and value ranges we depend on, run as pipeline targets
# so broken assumptions fail fast. contract_conference_tiers() lives in
# conference_tiers.R; these cover the other core datasets. Kept intentionally
# shallow for the skeleton — tighten as features land.

#' Run a contract and optionally abort
#'
#' @param agent An interrogated pointblank agent.
#' @param label Dataset label for the error message.
#' @param stop_on_fail Abort on failure?
#' @return The agent, invisibly.
#' @keywords internal
enforce_contract <- function(agent, label, stop_on_fail) {
  if (stop_on_fail && !pointblank::all_passed(agent)) {
    cli::cli_abort("The {.val {label}} data contract failed.")
  }
  invisible(agent)
}

#' Enforce contract results in the pipeline
#'
#' Stops the build when any contract's pass/fail record is `FALSE` (decision
#' 0023): the `ok_*` targets record per-table outcomes for the audit log, and
#' this gate is the enforcement point that makes a failing contract block
#' `tar_make()`. Steps without a contract (`NA`) are not failures — they are
#' tracked separately in audit-hygiene workstream C.
#'
#' @param results A named list or vector of contract outcomes (`TRUE`/`FALSE`/
#'   `NA`), e.g. `list(picks = ok_picks, roster = ok_roster)`.
#'
#' @return `TRUE` invisibly when every non-`NA` result passed.
#' @export
assert_contracts_pass <- function(results) {
  failed <- names(results)[!is.na(results) & !unlist(results)]
  if (length(failed) > 0) {
    cli::cli_abort(
      c(
        "{length(failed)} data contract{?s} failed: {.val {failed}}.",
        "i" = "Inspect the audit log and the failing contracts before rebuilding."
      ),
      call = rlang::caller_env()
    )
  }
  invisible(TRUE)
}

#' Data contract for cleaned picks
#'
#' @param picks Cleaned picks (see [clean_picks()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_picks <- function(picks, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  # Raw picks carry the full NFL draft history (back to 1936), not just our
  # 2010-2026 stats window; bound the year check accordingly.
  agent <- pointblank::create_agent(picks, label = "picks") |>
    pointblank::col_exists(c("collegeAthleteId", "year", "round", "overall")) |>
    # Columns documented in inst/dict/picks.yml that clean_picks passes through.
    pointblank::col_exists(c(
      "nflAthleteId",
      "collegeId",
      "collegeConference",
      "nflTeamId",
      "nflTeam",
      "pick",
      "name",
      "preDraftPositionRanking",
      "preDraftGrade",
      "hometownInfo_city",
      "hometownInfo_country",
      "hometownInfo_latitude",
      "hometownInfo_longitude",
      "hometownInfo_countyFips"
    )) |>
    pointblank::col_vals_between("year", 1936, 2027) |>
    pointblank::col_vals_between("round", 1, 30, na_pass = TRUE) |>
    # Grain: one draft pick, keyed by slot (year, round, pick). `collegeAthleteId`
    # is NOT unique — CFBD recycles ids across people (decision 0022), even
    # within a draft year (two different Derrick Johnsons at Texas in 2005
    # share one id) — so the slot, not the id, is the asserted key.
    pointblank::rows_distinct(pointblank::vars(year, round, pick)) |>
    pointblank::interrogate()
  enforce_contract(agent, "picks", stop_on_fail)
}

#' Data contract for the player-season backbone
#'
#' Asserts the grain of [build_player_season()]: one row per
#' `(playerId, season, team)` — a player who switched schools mid-season
#' legitimately has two rows for one season — with non-null keys.
#'
#' @param player_season Player-season backbone (see [build_player_season()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_player_season <- function(player_season, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(player_season, label = "player_season") |>
    pointblank::col_exists(c("playerId", "season", "team")) |>
    pointblank::col_vals_not_null(pointblank::vars(playerId, season, team)) |>
    pointblank::rows_distinct(pointblank::vars(playerId, season, team)) |>
    # Seasons stay inside the data window.
    pointblank::col_vals_between("season", 2010, 2026) |>
    pointblank::interrogate()
  enforce_contract(agent, "player_season", stop_on_fail)
}

#' Data contract for cleaned long player stats
#'
#' @param player_stats Cleaned long stats (see [clean_player_stats()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_player_stats <- function(player_stats, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(player_stats, label = "player_stats") |>
    pointblank::col_exists(c(
      "season",
      "playerId",
      "team",
      "conference",
      "category",
      "statType",
      "stat"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(playerId, season)) |>
    pointblank::col_vals_between("season", 2010, 2026) |>
    pointblank::interrogate()
  enforce_contract(agent, "player_stats", stop_on_fail)
}

#' Data contract for cleaned coaches
#'
#' @param coaches Cleaned coaches (see [clean_coaches()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_coaches <- function(coaches, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(coaches, label = "coaches") |>
    pointblank::col_exists(c("coach_id", "school", "season", "srs", "wins")) |>
    pointblank::col_vals_not_null(pointblank::vars(coach_id, school, season)) |>
    pointblank::col_vals_between("season", 1869, 2027) |>
    pointblank::interrogate()
  enforce_contract(agent, "coaches", stop_on_fail)
}

#' Data contract for the team dimension
#'
#' Validates the cleaned team dimension and, crucially, its *coverage*: every
#' `team` present in the player-season backbone must resolve to a row so a
#' logo/color join never silently drops a program. Logo *presence* is not a hard
#' check — a few small programs legitimately carry no logo URL (a placeholder is
#' used at display time), so that is left to a softer signal.
#'
#' @param teams Cleaned team dimension (see [clean_teams()]).
#' @param player_season Player-season backbone (see [build_player_season()]); the
#'   coverage universe the dimension must fully cover.
#' @param stop_on_fail If `TRUE` (default), raise an error when any check fails.
#'
#' @return Invisibly, a list of the two interrogated `pointblank` agents
#'   (`dim`, `coverage`).
#' @export
contract_teams <- function(teams, player_season, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  teams <- dplyr::collect(teams)
  player_season <- dplyr::collect(player_season)

  agent_dim <-
    pointblank::create_agent(teams, label = "teams: dimension") |>
    pointblank::col_exists(c(
      "team",
      "logo_light",
      "logo_dark",
      "conference"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(team)) |>
    pointblank::rows_distinct(pointblank::vars(team)) |>
    pointblank::interrogate()

  # Referential coverage: every player_season team has a dimension row.
  coverage <- player_season |>
    dplyr::distinct(.data$team) |>
    dplyr::filter(!is.na(.data$team)) |>
    dplyr::left_join(
      dplyr::transmute(teams, team = .data$team, has_row = TRUE),
      by = "team"
    ) |>
    dplyr::mutate(has_row = !is.na(.data$has_row))

  agent_coverage <-
    pointblank::create_agent(coverage, label = "teams: coverage") |>
    pointblank::col_vals_equal("has_row", TRUE) |>
    pointblank::interrogate()

  if (stop_on_fail) {
    if (!pointblank::all_passed(agent_dim)) {
      cli::cli_abort("The {.file teams} dimension failed its data contract.")
    }
    if (!pointblank::all_passed(agent_coverage)) {
      missing <- dplyr::filter(coverage, !.data$has_row)
      cli::cli_abort(c(
        "The {.file teams} dimension does not cover all of {.var player_season}.",
        "x" = "{nrow(missing)} team{?s} unmapped.",
        "i" = "e.g. {.val {utils::head(missing$team, 3)}}"
      ))
    }
  }

  invisible(list(dim = agent_dim, coverage = agent_coverage))
}

#' Data contract for the draft-outcome join
#'
#' Guards the outcome-defining join in [link_drafted()]: it must be strictly
#' 1:1 on `playerId` (no fan-out from historical id collisions, decision 0011),
#' the `drafted` flag must be a complete logical, and any `draft_year` must fall
#' inside the stats window.
#'
#' @param ps_draft Player-seasons with the draft outcome attached (see
#'   [link_drafted()]).
#' @param ps_pre The immediate pre-join input to [link_drafted()] (in the
#'   pipeline, `ps_tier` — already carrying the intentional `link_coaches`
#'   many-to-many inflation); its row count is what `ps_draft` must preserve.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_drafted <- function(ps_draft, ps_pre, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  ps_draft <- dplyr::collect(ps_draft)
  n_expected <- nrow(dplyr::collect(ps_pre))
  agent <- pointblank::create_agent(ps_draft, label = "drafted") |>
    pointblank::col_exists(c(
      "drafted",
      "draft_year",
      "draft_round",
      "draft_overall"
    )) |>
    # No fan-out: the join preserves the backbone row count exactly.
    pointblank::col_vals_equal("n", n_expected, preconditions = function(x) {
      dplyr::mutate(x, n = nrow(x))
    }) |>
    pointblank::col_vals_not_null(pointblank::vars(drafted)) |>
    pointblank::col_is_logical(pointblank::vars(drafted)) |>
    pointblank::col_vals_between(
      "draft_year",
      2010,
      2027,
      na_pass = TRUE
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "drafted", stop_on_fail)
}

#' Data contract for the coach link
#'
#' Asserts the sanctioned fan-out of [link_coaches()]: every
#' `(playerId, season, team)` key from the backbone appears exactly once when
#' its school-season has no recorded head coach, else once per recorded coach —
#' so the row count is pinned to the coaches table, not merely "bigger."
#'
#' @param ps_coach Player-seasons with coach context (see [link_coaches()]).
#' @param player_season Player-season backbone (see [build_player_season()]).
#' @param coaches Cleaned coaches (see [clean_coaches()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_coach_link <- function(
  ps_coach,
  player_season,
  coaches,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  expected <- player_season |>
    dplyr::count(.data$team, .data$season, name = "n_keys") |>
    dplyr::left_join(
      dplyr::count(coaches, school, season, name = "n_coaches"),
      by = c("team" = "school", "season")
    ) |>
    dplyr::mutate(n_coaches = dplyr::coalesce(.data$n_coaches, 0L)) |>
    dplyr::summarise(
      expected = sum(.data$n_keys * pmax(1L, .data$n_coaches))
    ) |>
    dplyr::pull(.data$expected)
  agent <- pointblank::create_agent(ps_coach, label = "coach_link") |>
    pointblank::col_exists(c(
      "coach_id",
      "coach_name",
      "games",
      "wins",
      "losses",
      "srs",
      "sp_overall",
      "sp_defense"
    )) |>
    pointblank::col_vals_not_null(
      pointblank::vars(playerId, season, team)
    ) |>
    pointblank::col_vals_equal("n", expected, preconditions = function(x) {
      dplyr::mutate(x, n = nrow(x))
    }) |>
    pointblank::interrogate()
  enforce_contract(agent, "coach_link", stop_on_fail)
}

#' Data contract for the tier link
#'
#' Asserts [link_tiers()] preserved the backbone row count and attached a
#' valid season-aware tier to every row (coverage of the lookup itself is
#' guaranteed by [contract_conference_tiers()]).
#'
#' @param ps_tier Player-seasons with tiers (see [link_tiers()]).
#' @param ps_coach Player-seasons with coach context (see [link_coaches()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_tier_link <- function(ps_tier, ps_coach, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(ps_tier, label = "tier_link") |>
    pointblank::col_exists(c("tier", "tier_label")) |>
    pointblank::col_vals_not_null(pointblank::vars(tier, tier_label)) |>
    pointblank::col_vals_between("tier", 1, 3) |>
    pointblank::col_vals_in_set(
      pointblank::vars(tier_label),
      c("Power", "Group of 5", "FCS and below")
    ) |>
    pointblank::col_vals_equal(
      "n",
      nrow(ps_coach),
      preconditions = function(x) {
        dplyr::mutate(x, n = nrow(x))
      }
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "tier_link", stop_on_fail)
}

#' Data contract for the reused-id filter
#'
#' Asserts the model population ([reused_ids()], decision 0022) is exactly the
#' drafted link minus rows whose `playerId` is a reused id — the filter drops
#' rows, never adds or mutates them.
#'
#' @param ps_pop Filtered model population (the `ps_pop` target).
#' @param ps_draft Player-seasons with draft flags (see [link_drafted()]).
#' @param reused Character vector of reused ids (see [reused_ids()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_reused_filter <- function(
  ps_pop,
  ps_draft,
  reused,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  expected <- sum(!ps_draft$playerId %in% reused)
  agent <- pointblank::create_agent(ps_pop, label = "reused_filter") |>
    pointblank::col_vals_not_null(
      pointblank::vars(playerId, season, team)
    ) |>
    pointblank::col_vals_expr(
      rlang::expr(!.data$reused_flag),
      preconditions = function(x) {
        dplyr::mutate(x, reused_flag = .data$playerId %in% reused)
      }
    ) |>
    pointblank::col_vals_equal("n", expected, preconditions = function(x) {
      dplyr::mutate(x, n = nrow(x))
    }) |>
    pointblank::interrogate()
  enforce_contract(agent, "reused_filter", stop_on_fail)
}

#' Data contract for change features
#'
#' Asserts [add_change_features()] is row-preserving and that the lag-derived
#' flags equal their definitions (no drift between formula and data):
#' `transferred` / `hc_changed` compare the previous observed season, and
#' `followed_coach` combines both. `hc_changed` / `followed_coach` may be `NA`
#' when a coach record is missing on either side (the comparison is then
#' unknowable, not FALSE) — the contract compares both sides `NA`-coalesced
#' to `FALSE` so the flag always agrees with its definition.
#'
#' @param ps_change Player-seasons with change features
#'   (see [add_change_features()]).
#' @param ps_pop Model population (the `ps_pop` target).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_change_features <- function(ps_change, ps_pop, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(ps_change, label = "change_features") |>
    pointblank::col_exists(c(
      "prev_team",
      "prev_tier",
      "prev_coach_id",
      "transferred",
      "transfer_direction",
      "hc_changed",
      "followed_coach"
    )) |>
    pointblank::col_is_logical(
      pointblank::vars(transferred, hc_changed, followed_coach)
    ) |>
    pointblank::col_vals_expr(
      rlang::expr(
        is.na(.data$transfer_direction) |
          .data$transfer_direction %in% c("up", "down", "lateral")
      )
    ) |>
    pointblank::col_vals_expr(
      rlang::expr(
        .data$transferred ==
          (!is.na(.data$prev_team) &
            .data$team != .data$prev_team)
      )
    ) |>
    pointblank::col_vals_expr(
      rlang::expr(
        dplyr::coalesce(.data$hc_changed, FALSE) ==
          dplyr::coalesce(
            !is.na(.data$prev_coach_id) &
              !is.na(.data$coach_id) &
              (.data$coach_id != .data$prev_coach_id),
            FALSE
          )
      )
    ) |>
    pointblank::col_vals_expr(
      rlang::expr(
        dplyr::coalesce(.data$followed_coach, FALSE) ==
          dplyr::coalesce(
            .data$transferred &
              !is.na(.data$prev_coach_id) &
              !is.na(.data$coach_id) &
              (.data$coach_id == .data$prev_coach_id),
            FALSE
          )
      )
    ) |>
    pointblank::col_vals_equal("n", nrow(ps_pop), preconditions = function(x) {
      dplyr::mutate(x, n = nrow(x))
    }) |>
    pointblank::interrogate()
  enforce_contract(agent, "change_features", stop_on_fail)
}

#' Data contract for the roster-weight attachment
#'
#' Asserts [add_roster_weight()] is row-preserving and the attached static
#' weight stays in the plausible 100-500 lb range (NA where the roster has no
#' weight — ~19% of player-seasons, decision 0009).
#'
#' @param model_table Model table with weight (see [add_roster_weight()]).
#' @param ps_change Player-seasons with change features
#'   (see [add_change_features()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_roster_weight <- function(
  model_table,
  ps_change,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(model_table, label = "roster_weight") |>
    pointblank::col_exists("weight") |>
    pointblank::col_vals_between("weight", 100, 500, na_pass = TRUE) |>
    pointblank::col_vals_equal(
      "n",
      nrow(ps_change),
      preconditions = function(x) {
        dplyr::mutate(x, n = nrow(x))
      }
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "roster_weight", stop_on_fail)
}

#' Data contract for the recruiting link
#'
#' Asserts [link_recruiting()] is row-preserving, the HS rating columns stay
#' in their documented ranges, and the name guard is honored: unmatched rows
#' carry no HS values (matched rows may still lack `stars`/`rating` when the
#' feed omits them).
#'
#' @param ps_recruit Player-seasons with HS recruiting ratings
#'   (see [link_recruiting()]).
#' @param player_season Player-season backbone (see [build_player_season()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_recruit_link <- function(
  ps_recruit,
  player_season,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(ps_recruit, label = "recruit_link") |>
    pointblank::col_exists(c(
      "recruit_matched",
      "hs_stars",
      "hs_rating",
      "hs_national_rank",
      "hs_class"
    )) |>
    pointblank::col_is_logical(pointblank::vars(recruit_matched)) |>
    pointblank::col_vals_between("hs_stars", 0, 5, na_pass = TRUE) |>
    pointblank::col_vals_between("hs_rating", 0, 1, na_pass = TRUE) |>
    # Unmatched rows carry no HS values; matched rows may or may not.
    pointblank::col_vals_expr(
      rlang::expr(
        .data$recruit_matched |
          (is.na(.data$hs_stars) & is.na(.data$hs_rating))
      )
    ) |>
    pointblank::col_vals_equal(
      "n",
      nrow(player_season),
      preconditions = function(x) {
        dplyr::mutate(x, n = nrow(x))
      }
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "recruit_link", stop_on_fail)
}

#' Data contract for cleaned rosters
#'
#' Guards the roster backbone: the `(playerId, season, team)` key is unique
#' (a player-team-season may appear once; a player legitimately appears on
#' multiple teams within a season, so the team is part of the key), and
#' `class_year` is a plausible eligibility class (1-5 or NA — `clean_roster()`
#' coerces CFBD's year-valued contamination to NA, decision 0009 precedent).
#'
#' @param roster Cleaned roster (see [clean_roster()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_roster <- function(roster, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(roster, label = "roster") |>
    pointblank::col_exists(c("playerId", "season", "weight", "height")) |>
    pointblank::col_vals_not_null(pointblank::vars(playerId, season)) |>
    pointblank::col_vals_between("weight", 100, 500, na_pass = TRUE) |>
    pointblank::col_vals_between("height", 60, 85, na_pass = TRUE) |>
    pointblank::rows_distinct(pointblank::vars(playerId, season, team)) |>
    pointblank::col_vals_between("class_year", 1L, 5L, na_pass = TRUE) |>
    pointblank::interrogate()
  enforce_contract(agent, "roster", stop_on_fail)
}

#' Data contract for redshirt flags
#'
#' Sanity-checks the redshirt flags ([flag_redshirt()], Explore question 12):
#' flag columns exist and are never null, and a redshirt-shaped season always
#' lacks a stat line (the flag's definition). The flags are approximate by
#' design — see the function docs — so no stronger bound is asserted here.
#'
#' @param roster_flagged Roster with redshirt flags (see [flag_redshirt()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_redshirt <- function(roster_flagged, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(
    roster_flagged,
    label = "redshirt"
  ) |>
    pointblank::col_exists(c(
      "has_stats",
      "redshirt_season",
      "redshirt_career",
      "fifth_year_career"
    )) |>
    pointblank::col_vals_not_null(
      pointblank::vars(has_stats, redshirt_season, redshirt_career)
    ) |>
    # A redshirt-shaped season must lack a stat line.
    pointblank::col_vals_expr(
      rlang::expr(!.data$has_stats | !.data$redshirt_season)
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "redshirt", stop_on_fail)
}

#' Data contract for career summaries
#'
#' Validates the per-player career table ([career_summary()]) against the
#' Explore plan's career-length bounds: 1-7 seasons on a roster (CFBD
#' rosters cover 2010-2026, so a longer span implies duplicate identities),
#' and no negative gaps or transfers.
#'
#' @param career Per-player career summary (see [career_summary()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_career_summary <- function(career, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(career, label = "career_summary") |>
    pointblank::col_exists(c(
      "playerId",
      "seasons",
      "first_season",
      "last_season",
      "gap_seasons",
      "transfers"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(playerId, seasons)) |>
    pointblank::rows_distinct(pointblank::vars(playerId)) |>
    pointblank::col_vals_between("seasons", 1L, 7L) |>
    pointblank::col_vals_gte("gap_seasons", 0L) |>
    pointblank::col_vals_between("transfers", 0L, 6L) |>
    pointblank::interrogate()
  enforce_contract(agent, "career_summary", stop_on_fail)
}

#' Data contract for career endings
#'
#' Validates [career_end_status()] (issue #51, part 1; decision 0039). One row
#' per career, so the row count equals the career universe (no silent row loss).
#' Every career gets exactly one category from `career_end_levels`, so the
#' categories are exhaustive and mutually exclusive. Censored careers are never
#' early stops, and the early-stop proxy flag is exactly the `early_stop`
#' category with its defining conditions (single school, eligibility left, no
#' NFL entry, not censored).
#'
#' @param career_end Output of [career_end_status()].
#' @param career Per-player career summary the table was built from; its row
#'   count is the expected row count.
#' @param stop_on_fail Abort on failure? `FALSE` records the result for the
#'   audit log instead (the `ok_*` target pattern).
#'
#' @return The interrogated pointblank agent (invisible).
#' @export
contract_career_end <- function(career_end, career, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  expected <- nrow(career)
  agent <- pointblank::create_agent(career_end, label = "career_end") |>
    pointblank::col_exists(c(
      "playerId",
      "career_end",
      "early_stop_proxy",
      "right_censored",
      "eligibility_remaining",
      "clock_seasons_used",
      "transfers",
      "drafted",
      "signed_udfa",
      "in_model_population"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(playerId, career_end)) |>
    pointblank::col_vals_equal(
      pointblank::vars(n),
      expected,
      preconditions = function(x) {
        dplyr::mutate(x, n = nrow(x))
      }
    ) |>
    pointblank::rows_distinct(pointblank::vars(playerId)) |>
    pointblank::col_vals_in_set(
      pointblank::vars(career_end),
      set = names(career_end_levels)
    ) |>
    pointblank::col_vals_expr(rlang::expr(
      right_censored == (career_end == "right_censored")
    )) |>
    pointblank::col_vals_expr(rlang::expr(
      early_stop_proxy == (career_end == "early_stop")
    )) |>
    # The proxy's defining conditions, restated so a rule change cannot drift.
    pointblank::col_vals_expr(rlang::expr(
      !early_stop_proxy |
        (!right_censored &
          !drafted &
          !signed_udfa &
          in_model_population &
          transfers == 0L &
          eligibility_remaining > 0L)
    )) |>
    pointblank::col_vals_expr(rlang::expr(
      !(drafted & signed_udfa)
    )) |>
    pointblank::interrogate()
  enforce_contract(agent, "career_end", stop_on_fail)
}

#' Data contract for the team-season table
#'
#' Guards [build_team_season()]: one row per `(team, season)`, a record that
#' adds up, `win_pct` in 0 to 1 (NA exactly when no games), non-negative counts, and a tier on every FBS
#' team-season (an untiered FBS conference means the tier lookup is stale).
#'
#' @param team_season Output of [build_team_season()].
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_team_season <- function(team_season, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(team_season, label = "team_season") |>
    pointblank::col_exists(c(
      "team",
      "season",
      "conference",
      "tier",
      "games_played",
      "wins",
      "losses",
      "ties",
      "win_pct",
      "n_roster",
      "n_stat_players"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(team, season)) |>
    pointblank::rows_distinct(pointblank::vars(team, season)) |>
    pointblank::col_vals_expr(rlang::expr(
      wins + losses + ties == games_played
    )) |>
    pointblank::col_vals_between("win_pct", 0, 1, na_pass = TRUE) |>
    pointblank::col_vals_expr(rlang::expr(
      is.na(win_pct) == (games_played == 0L)
    )) |>
    # Row floor: an empty table must not pass vacuously.
    pointblank::col_vals_gt(
      "n",
      0L,
      preconditions = function(x) tibble::tibble(n = nrow(x))
    ) |>
    pointblank::col_vals_gte(
      pointblank::vars(games_played, n_roster, n_stat_players),
      0L
    ) |>
    pointblank::col_vals_not_null(
      pointblank::vars(tier),
      preconditions = function(x) {
        dplyr::filter(x, .data$classification %in% "fbs")
      }
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "team_season", stop_on_fail)
}

#' Data contract for the team draft table
#'
#' Guards [build_team_draft()]: one row per `(team, season, position_group)`;
#' drafted + UDFA <= eligible <= exits; exit totals equal the cohort (no
#' silent loss in aggregation); and at least `min_coverage` of id-bearing,
#' non-reused picks from `min_class` on are attributed to a team (picks with
#' no roster season before the draft cannot be credited).
#'
#' @param team_draft Output of [build_team_draft()].
#' @param cohort Output of [exit_cohort()].
#' @param picks Cleaned picks.
#' @param reused Reused athlete ids ([reused_ids()]).
#' @param min_class First draft class in the coverage check.
#' @param draft_window Plausible draft years; picks after `max(draft_window)`
#'   are outside the cohort and not counted in the coverage denominator.
#' @param min_coverage Minimum attributed share (default 0.93; 94.6% observed
#'   2026-10-31).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_team_draft <- function(
  team_draft,
  cohort,
  picks,
  reused,
  min_class = 2014L,
  min_coverage = 0.93,
  draft_window = 2010:2027,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  n_picks <- picks |>
    dplyr::filter(
      !is.na(.data$playerId),
      !.data$playerId %in% reused,
      .data$year >= min_class,
      .data$year <= max(draft_window)
    ) |>
    dplyr::distinct(.data$playerId) |>
    nrow()
  n_attributed <- sum(cohort$drafted & cohort$draft_class >= min_class)
  coverage <- if (n_picks > 0) n_attributed / n_picks else 1
  n_cohort <- nrow(cohort)
  agent <- pointblank::create_agent(team_draft, label = "team_draft") |>
    pointblank::rows_distinct(pointblank::vars(team, season, position_group)) |>
    pointblank::col_vals_not_null(pointblank::vars(tier, tier_label)) |>
    # Row floor: an empty table must not pass vacuously.
    pointblank::col_vals_gt(
      "n",
      0L,
      preconditions = function(x) tibble::tibble(n = nrow(x))
    ) |>
    pointblank::col_vals_in_set(
      "position_group",
      c(position_group_levels(), "Position not recorded")
    ) |>
    pointblank::col_vals_expr(rlang::expr(n_drafted + n_udfa <= n_eligible)) |>
    pointblank::col_vals_expr(rlang::expr(n_eligible <= n_exits)) |>
    pointblank::col_vals_expr(rlang::expr(n_round1 <= n_drafted)) |>
    pointblank::col_vals_equal(
      "total_exits",
      n_cohort,
      preconditions = function(x) {
        tibble::tibble(total_exits = sum(x$n_exits))
      }
    ) |>
    pointblank::col_vals_gte(
      "coverage",
      min_coverage,
      preconditions = function(x) tibble::tibble(coverage = .env$coverage)
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "team_draft", stop_on_fail)
}

#' Data contract for cleaned recruiting ratings
#'
#' Validates the per-athlete recruiting-rating table ([clean_recruiting()]):
#' keyed 1:1 on a non-null `playerId`, with `stars`/`rating`/`national_rank` in
#' their documented ranges and the HS class inside a plausible window. The
#' wrong-person id-collision is a *join-time* concern handled by the name guard
#' in [link_recruiting()] (decision 0013), not asserted here.
#'
#' @param recruiting Cleaned recruiting (see [clean_recruiting()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_recruiting <- function(recruiting, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(recruiting, label = "recruiting") |>
    pointblank::col_exists(c(
      "playerId",
      "recruit_name",
      "hs_class",
      "stars",
      "rating",
      "national_rank"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(playerId)) |>
    pointblank::rows_distinct(pointblank::vars(playerId)) |>
    pointblank::col_vals_between("stars", 2, 5, na_pass = TRUE) |>
    # Composite is a 0-1 index by construction; most rated players sit ~0.7-1.0
    # but a tail of 2-stars dips lower, so bound structurally at [0, 1].
    pointblank::col_vals_between("rating", 0, 1.0, na_pass = TRUE) |>
    pointblank::col_vals_between("hs_class", 2010, 2027, na_pass = TRUE) |>
    pointblank::interrogate()
  enforce_contract(agent, "recruiting", stop_on_fail)
}

# ---- NFL outcomes via nflverse (decision 0014) ------------------------------

#' Data contract for cleaned NFL draft picks (nflverse)
#'
#' Asserts the bridge/career table ([clean_nfl_draft_picks()]) is keyed 1:1 on
#' the draft slot (`season`/`round`/`pick`) — the join key to CFBD picks — with
#' the season inside the nflverse window and career counts non-negative.
#'
#' @param nfl_draft_picks Cleaned nflverse draft picks.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_nfl_draft_picks <- function(nfl_draft_picks, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(
    nfl_draft_picks,
    label = "nfl_draft_picks"
  ) |>
    pointblank::col_exists(c(
      "season",
      "round",
      "pick",
      "gsis_id",
      "pfr_player_id",
      "pfr_player_name",
      "to",
      "games",
      "seasons_started"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(season, round, pick)) |>
    pointblank::rows_distinct(pointblank::vars(season, round, pick)) |>
    pointblank::col_vals_between("season", 2010, 2026) |>
    pointblank::col_vals_gte("games", 0, na_pass = TRUE) |>
    pointblank::interrogate()
  enforce_contract(agent, "nfl_draft_picks", stop_on_fail)
}

#' Data contract for cleaned NFL rosters (nflverse)
#'
#' Asserts the roster table ([clean_nfl_rosters()]) is keyed 1:1 on
#' `gsis_id` × `season` (the basis for the roster-seasons longevity measure),
#' with the season inside the window and weight in a plausible NFL range.
#'
#' @param nfl_rosters Cleaned nflverse rosters.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_nfl_rosters <- function(nfl_rosters, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(nfl_rosters, label = "nfl_rosters") |>
    pointblank::col_exists(c(
      "gsis_id",
      "season",
      "player_name",
      "nfl_team",
      "years_exp"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(gsis_id, season)) |>
    pointblank::rows_distinct(pointblank::vars(gsis_id, season)) |>
    pointblank::col_vals_between("season", 2010, 2026) |>
    pointblank::col_vals_between("weight", 100, 500, na_pass = TRUE) |>
    pointblank::interrogate()
  enforce_contract(agent, "nfl_rosters", stop_on_fail)
}

#' Data contract for cleaned NFL player stats (nflverse)
#'
#' Asserts the season-aggregated stats table ([clean_nfl_player_stats()]) is
#' keyed 1:1 on `gsis_id` × `season`, in-window, with non-negative counting
#' totals.
#'
#' @param nfl_player_stats Cleaned nflverse player-season stats.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_nfl_player_stats <- function(nfl_player_stats, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(
    nfl_player_stats,
    label = "nfl_player_stats"
  ) |>
    pointblank::col_exists(c(
      "gsis_id",
      "season",
      "games",
      "pass_yards",
      "rush_yards",
      "rec_yards"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(gsis_id, season)) |>
    pointblank::rows_distinct(pointblank::vars(gsis_id, season)) |>
    pointblank::col_vals_between("season", 2010, 2026) |>
    pointblank::col_vals_gte("games", 0) |>
    pointblank::interrogate()
  enforce_contract(agent, "nfl_player_stats", stop_on_fail)
}

#' Data contract for the NFL draft-slot bridge
#'
#' Guards [link_nfl_draft()]: the slot join must preserve the `picks` row count
#' exactly (nflverse slots are unique, so no fan-out), `nfl_matched` must be a
#' complete logical, and an attached `gsis_id` must imply a validated
#' name-guarded match.
#'
#' @param picks_nfl Picks with nflverse ids attached (see [link_nfl_draft()]).
#' @param picks The pre-join CFBD picks; its row count is what `picks_nfl` must
#'   preserve.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_nfl_link <- function(picks_nfl, picks, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  n_expected <- nrow(picks)
  check <- picks_nfl |>
    dplyr::mutate(
      # An attached id must coincide with a validated match.
      id_implies_match = is.na(.data$gsis_id) | .data$nfl_matched
    )
  agent <- pointblank::create_agent(check, label = "nfl_link") |>
    pointblank::col_exists(c("gsis_id", "pfr_player_id", "nfl_matched")) |>
    pointblank::col_is_logical(pointblank::vars(nfl_matched)) |>
    pointblank::col_vals_not_null(pointblank::vars(nfl_matched)) |>
    pointblank::col_vals_equal("n", n_expected, preconditions = function(x) {
      dplyr::mutate(x, n = nrow(x))
    }) |>
    pointblank::col_vals_equal("id_implies_match", TRUE) |>
    pointblank::interrogate()
  enforce_contract(agent, "nfl_link", stop_on_fail)
}

#' Data contract for the linked NFL combine table
#'
#' Guards [clean_combine()] + [link_combine()] (decision 0043): one row per
#' invitee on `(season, player_name, school, pos)`, measurables inside
#' [combine_ranges], `link_method` in its three values with `athlete_id` set
#' exactly when linked, an id linked at most once per combine, link-rate
#' floors (drafted invitees from draft year 2013 on, the window where CFBD
#' picks carry ids, at `min_drafted_rate`; undrafted invitees from 2011 on,
#' when their final season is in the CFBD window, at `min_undrafted_rate`),
#' and the slot `pfr_id` cross-check disagreeing on at most 1% of drafted rows.
#'
#' @param combine Linked combine table (the published `combine` parquet).
#' @param n_expected Optional pre-link row count (the ingested rows); when
#'   given, the link must preserve it exactly.
#' @param min_drafted_rate,min_undrafted_rate Link-rate floors.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_combine <- function(
  combine,
  n_expected = NULL,
  min_drafted_rate = 0.95,
  min_undrafted_rate = 0.6,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  rate <- function(rows) {
    if (!any(rows)) {
      return(1)
    }
    mean(!is.na(combine$athlete_id[rows]))
  }
  drafted <- !is.na(combine$draft_ovr) & combine$draft_year >= 2013L
  undrafted <- is.na(combine$draft_ovr) & combine$season >= 2011L
  slot <- !is.na(combine$pfr_agrees)
  linked <- combine[!is.na(combine$athlete_id), c("season", "athlete_id")]
  check <- combine |>
    dplyr::mutate(
      n = nrow(combine),
      id_iff_linked = is.na(.data$athlete_id) ==
        (.data$link_method == "unmatched"),
      drafted_rate = rate(drafted),
      undrafted_rate = rate(undrafted),
      pfr_disagree = if (any(slot)) mean(!combine$pfr_agrees[slot]) else 0,
      ids_unique = !anyDuplicated(linked)
    )
  agent <- pointblank::create_agent(check, label = "combine") |>
    pointblank::col_exists(c(
      "season",
      "player_name",
      "school",
      "pos",
      "athlete_id",
      "link_method",
      "pfr_agrees"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(season, player_name)) |>
    pointblank::rows_distinct(pointblank::vars(
      season,
      player_name,
      school,
      pos
    )) |>
    pointblank::col_vals_between("season", 2010, 2026)
  for (col in names(combine_ranges)) {
    agent <- pointblank::col_vals_between(
      agent,
      dplyr::all_of(col),
      combine_ranges[[col]][1],
      combine_ranges[[col]][2],
      na_pass = TRUE
    )
  }
  agent <- agent |>
    pointblank::col_vals_in_set(
      "link_method",
      c("draft_slot", "name_school", "unmatched")
    ) |>
    pointblank::col_vals_equal("id_iff_linked", TRUE) |>
    pointblank::col_vals_equal("ids_unique", TRUE) |>
    pointblank::col_vals_gte("drafted_rate", min_drafted_rate) |>
    pointblank::col_vals_gte("undrafted_rate", min_undrafted_rate) |>
    pointblank::col_vals_lte("pfr_disagree", 0.01)
  if (!is.null(n_expected)) {
    agent <- pointblank::col_vals_equal(agent, "n", n_expected)
  }
  agent <- pointblank::interrogate(agent)
  enforce_contract(agent, "combine", stop_on_fail)
}

#' Data contract for the college->NFL trajectory spine
#'
#' Guards [player_trajectory()] output: every spine row must carry a resolved
#' player (`who`), `team`, and `stage` — a null in any of these means a subject
#' id failed to join to a name or a roster row, which would silently break the
#' timeline figure and its caption. `stage` is also constrained to the two
#' expected values, and `drafted` must be a complete logical.
#'
#' @param spine Trajectory spine (see [player_trajectory()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_player_trajectory <- function(spine, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(spine, label = "player_trajectory") |>
    pointblank::col_exists(c("who", "team", "stage", "season", "drafted")) |>
    pointblank::col_vals_not_null(pointblank::vars(who, team, stage)) |>
    pointblank::col_vals_in_set("stage", c("College", "NFL")) |>
    pointblank::col_is_logical(pointblank::vars(drafted)) |>
    pointblank::col_vals_not_null(pointblank::vars(drafted)) |>
    pointblank::interrogate()
  enforce_contract(agent, "player_trajectory", stop_on_fail)
}

#' Data contract for the stat-phase taxonomy
#'
#' Validates the taxonomy lookup and, crucially, its *coverage*: every
#' `(category, statType)` pair present in `player_stats` must resolve to a
#' taxonomy row, so a new stat appearing in a refresh fails fast rather than
#' going silently unlabeled (the analogue of the conference-tier coverage
#' guard). Intended to run in the pipeline.
#'
#' @param player_stats Long player-season stats with `category` and `statType`;
#'   the coverage universe the taxonomy must fully cover.
#' @param taxonomy The taxonomy lookup; defaults to [stat_taxonomy()].
#' @param stop_on_fail If `TRUE` (default), raise an error when any check fails.
#'
#' @return Invisibly, a list of the two interrogated `pointblank` agents
#'   (`lookup`, `coverage`).
#' @export
contract_stat_taxonomy <- function(
  player_stats,
  taxonomy = stat_taxonomy(),
  stop_on_fail = TRUE
) {
  rlang::check_installed(
    "pointblank",
    reason = "to run the stat-taxonomy data contract."
  )
  taxonomy <- dplyr::collect(taxonomy)
  player_stats <- dplyr::collect(player_stats)

  # Intrinsic checks on the taxonomy table itself.
  agent_lookup <-
    pointblank::create_agent(taxonomy, label = "stat_taxonomy: lookup") |>
    pointblank::col_exists(
      c("category", "statType", "phase", "label", "kind")
    ) |>
    pointblank::col_vals_not_null(
      pointblank::vars(category, statType, phase, label, kind)
    ) |>
    pointblank::col_vals_in_set(
      "phase",
      c("offense", "defense", "special_teams")
    ) |>
    pointblank::col_vals_in_set("kind", c("scoring", "volume", "rate")) |>
    pointblank::rows_distinct(pointblank::vars(category, statType)) |>
    pointblank::interrogate()

  # Referential coverage: no (category, statType) in player_stats is unmapped.
  coverage <- player_stats |>
    dplyr::distinct(.data$category, .data$statType) |>
    dplyr::left_join(
      dplyr::transmute(
        taxonomy,
        .data$category,
        .data$statType,
        has_phase = TRUE
      ),
      by = c("category", "statType")
    ) |>
    dplyr::mutate(has_phase = !is.na(.data$has_phase))

  agent_coverage <-
    pointblank::create_agent(coverage, label = "stat_taxonomy: coverage") |>
    pointblank::col_vals_equal("has_phase", TRUE) |>
    pointblank::interrogate()

  if (stop_on_fail) {
    if (!pointblank::all_passed(agent_lookup)) {
      cli::cli_abort(
        "The {.file stat_taxonomy} lookup failed its data contract."
      )
    }
    if (!pointblank::all_passed(agent_coverage)) {
      missing <- dplyr::filter(coverage, !.data$has_phase)
      examples <- utils::head(paste(missing$category, missing$statType), 3)
      cli::cli_abort(c(
        "The {.file stat_taxonomy} does not cover all of {.var player_stats}.",
        "x" = "{nrow(missing)} (category, statType) pair{?s} unmapped.",
        "i" = "e.g. {.val {examples}}"
      ))
    }
  }

  invisible(list(lookup = agent_lookup, coverage = agent_coverage))
}

#' Data contract for the wide player-season stat table
#'
#' Validates the DuckDB-bundled wide stat table ([build_player_season_stats()]):
#' keyed 1:1 on `(playerId, season, team)`, key columns non-null, seasons in the
#' ingested window, and every stat column finite (the pivot casts `stat` to
#' double; Inf would mean a bad value in the feed). NOTE: stat columns may be
#' NEGATIVE (sack-adjusted rushing yards, return averages on negative plays),
#' so non-negativity is NOT asserted.
#'
#' @param player_season_stats Wide stat table (see [build_player_season_stats()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_player_season_stats <- function(
  player_season_stats,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  key_cols <- c(
    "playerId",
    "player",
    "season",
    "team",
    "conference",
    "position"
  )
  stat_cols <- setdiff(names(player_season_stats), key_cols)
  agent <- pointblank::create_agent(
    player_season_stats,
    label = "player_season_stats"
  ) |>
    pointblank::col_exists(pointblank::vars(!!!rlang::syms(key_cols))) |>
    pointblank::col_vals_not_null(pointblank::vars(playerId, season, team)) |>
    pointblank::rows_distinct(pointblank::vars(playerId, season, team)) |>
    pointblank::col_vals_between("season", 2010L, 2026L)
  # Finiteness for every stat column; NA (pair not logged) is skipped.
  # (pointblank has no col_vals_finite; expr form: is.na(.) | is.finite(.)).
  for (col in stat_cols) {
    agent <- pointblank::col_vals_expr(
      agent,
      expr = rlang::expr(
        is.na(!!rlang::sym(col)) | is.finite(!!rlang::sym(col))
      )
    )
  }
  agent <- pointblank::interrogate(agent)
  enforce_contract(agent, "player_season_stats", stop_on_fail)
}

#' Data contract for game metadata
#'
#' Validates one-row-per-game uniqueness (`id`), period bounds matching the
#' 2010–2026 ingest window, and required join columns.
#'
#' @param games Cleaned games (see [clean_games()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_games <- function(games, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(games, label = "games") |>
    pointblank::col_exists(c(
      "id",
      "season",
      "week",
      "seasonType",
      "homeTeam",
      "awayTeam",
      "homePoints",
      "awayPoints",
      "startDate",
      "completed"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(id, season, week)) |>
    pointblank::col_vals_between("season", 2010L, 2026L) |>
    pointblank::rows_distinct(pointblank::vars(id)) |>
    pointblank::interrogate()
  enforce_contract(agent, "games", stop_on_fail)
}

#' Data contract for team game statistics
#'
#' One row per team-game-category-stat; keys and period bounds enforced.
#'
#' @param game_team_stats Cleaned team game stats (see [clean_game_team_stats()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_game_team_stats <- function(game_team_stats, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(
    game_team_stats,
    label = "game_team_stats"
  ) |>
    pointblank::col_exists(c(
      "gameId",
      "season",
      "week",
      "seasonType",
      "team",
      "category",
      "stat"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(gameId, team, category)) |>
    pointblank::col_vals_between("season", 2010L, 2026L) |>
    pointblank::rows_distinct(pointblank::vars(gameId, team, category)) |>
    pointblank::interrogate()
  enforce_contract(agent, "game_team_stats", stop_on_fail)
}

#' Data contract for player game statistics
#'
#' One row per player-game-category-statType-stat; `playerId` must be present
#' (the shared athlete-id namespace) and period bounds enforced.
#'
#' @param game_player_stats Cleaned player game stats (see
#'   [clean_game_player_stats()]).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_game_player_stats <- function(
  game_player_stats,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(
    game_player_stats,
    label = "game_player_stats"
  ) |>
    pointblank::col_exists(c(
      "gameId",
      "season",
      "week",
      "seasonType",
      "team",
      "category",
      "statType",
      "playerId",
      "stat"
    )) |>
    pointblank::col_vals_not_null(
      pointblank::vars(gameId, playerId, category, statType)
    ) |>
    pointblank::col_vals_between("season", 2010L, 2026L) |>
    pointblank::rows_distinct(
      pointblank::vars(gameId, playerId, category, statType)
    ) |>
    pointblank::specially(
      fn = box_scores_list_many_players,
      label = "most team-games list more than one rusher"
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "game_player_stats", stop_on_fail)
}

# Whole box scores, not one player per stat type: a flatten that keeps only
# the first athlete (the 2026-11 bug) leaves exactly one rusher per team-game.
# Real team-games almost always list two or more, so at least half must.
# Judged only on 100+ team-games, so small test fixtures pass.
box_scores_list_many_players <- function(x, min_team_games = 100L) {
  rushers <- x |>
    dplyr::filter(.data$category == "rushing", .data$statType == "CAR") |>
    dplyr::count(.data$gameId, .data$team, name = "n_players")
  nrow(rushers) < min_team_games || mean(rushers$n_players > 1L) >= 0.5
}

#' Data contract for a play-by-play dimension
#'
#' Shared by `play_types` and `play_stat_types` (decision 0031): a non-null,
#' unique integer `id`, a label column, and at least `min_rows` rows, so an
#' empty or truncated dimension fails before the plays lose their labels.
#'
#' @param dim Cleaned dimension ([clean_play_types()] or
#'   [clean_play_stat_types()]).
#' @param label_col The label column (`"text"` or `"name"`).
#' @param label Dataset label.
#' @param min_rows Smallest plausible row count.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_play_dimension <- function(
  dim,
  label_col,
  label,
  min_rows,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(dim, label = label) |>
    pointblank::col_exists(dplyr::all_of(c("id", label_col))) |>
    pointblank::col_vals_not_null(dplyr::all_of(c("id", label_col))) |>
    pointblank::rows_distinct(pointblank::vars(id)) |>
    pointblank::specially(
      fn = function(x) nrow(x) >= min_rows,
      label = paste("at least", min_rows, "rows")
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, label, stop_on_fail)
}

#' Data contract for plays
#'
#' One row per play, keyed by `id` (decision 0031). Every `gameId` is a real
#' game, every played FBS week has plays, every play type maps to the
#' dimension, and the situational columns stay in the ranges [clean_plays()]
#' normalizes to: `down` 0 to 4 (0 on kickoffs and
#' other non-scrimmage plays), `yardsToGoal` 0 to 100, `period` 1 or more
#' (overtimes run past 4).
#'
#' @param plays Cleaned plays ([clean_plays()]).
#' @param games Cleaned games (the game-id reference set).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_plays <- function(plays, games, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(plays, label = "plays") |>
    pointblank::col_exists(c(
      "id",
      "gameId",
      "driveId",
      "season",
      "week",
      "seasonType",
      "offense",
      "defense",
      "period",
      "down",
      "distance",
      "yardsToGoal",
      "playTypeId",
      "playType",
      "ppa"
    )) |>
    pointblank::col_vals_not_null(
      pointblank::vars(id, gameId, season, week, seasonType)
    ) |>
    pointblank::rows_distinct(pointblank::vars(id)) |>
    pointblank::col_vals_between("season", 2010L, 2026L) |>
    pointblank::col_vals_between("down", 0L, 4L, na_pass = TRUE) |>
    pointblank::col_vals_between("yardsToGoal", 0L, 100L, na_pass = TRUE) |>
    pointblank::col_vals_gte("period", 1L, na_pass = TRUE) |>
    pointblank::specially(
      fn = function(x) all(unique(x$gameId) %in% games$id),
      label = "every gameId is in games"
    ) |>
    pointblank::specially(
      fn = function(x) plays_cover_played_weeks(x, games),
      label = "every played week has plays"
    ) |>
    pointblank::specially(
      fn = function(x) !any(is.na(x$playTypeId) & !is.na(x$playType)),
      label = "every play type is in play_types"
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "plays", stop_on_fail)
}

# A week CFBD played with an FBS team in it must have plays: a failed or
# skipped week pull leaves a hole the row-count checks cannot see. Judged on
# the seasons present in `plays`, so a partial (test or backfill) table
# passes; season completeness is the season-coverage contract's job.
plays_cover_played_weeks <- function(plays, games) {
  played <- games |>
    dplyr::filter(
      .data$completed,
      .data$season %in% unique(plays$season),
      .data$homeClassification %in% "fbs" | .data$awayClassification %in% "fbs"
    ) |>
    dplyr::distinct(.data$season, .data$seasonType, .data$week)
  have <- dplyr::distinct(plays, .data$season, .data$seasonType, .data$week)
  nrow(dplyr::anti_join(
    played,
    have,
    by = c("season", "seasonType", "week")
  )) ==
    0L
}

#' Data contract for play stats
#'
#' One row per athlete-play-stat, keyed by `(playId, athleteId, statTypeId)`
#' (decision 0031). Guards the per-game pull: no game reaches the 2,000-row
#' cap that silently truncates the week grain, every play is a known play,
#' every stat type maps to the dimension, and `athleteId` stays in the shared
#' athlete namespace (at least `min_roster_share` of ids are roster
#' `playerId`s; 100% on the 2026-10 probe). An empty table (no season pulled
#' yet) passes.
#'
#' @param play_stats Cleaned play stats ([clean_play_stats()]).
#' @param plays Cleaned plays (the play-id reference set).
#' @param roster Cleaned roster (the athlete-id reference set).
#' @param min_roster_share Smallest share of distinct `athleteId`s on a roster.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_play_stats <- function(
  play_stats,
  plays,
  roster,
  min_roster_share = 0.95,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  agent <- pointblank::create_agent(play_stats, label = "play_stats") |>
    pointblank::col_exists(c(
      "gameId",
      "season",
      "playId",
      "athleteId",
      "statTypeId",
      "statType",
      "stat"
    )) |>
    pointblank::col_vals_not_null(
      pointblank::vars(gameId, season, playId, athleteId, statTypeId)
    ) |>
    pointblank::rows_distinct(
      pointblank::vars(playId, athleteId, statTypeId)
    ) |>
    pointblank::specially(
      fn = function(x) !any(table(x$gameId) >= 2000L),
      label = "no game hits the 2,000-row cap"
    ) |>
    pointblank::specially(
      fn = function(x) all(unique(x$playId) %in% plays$id),
      label = "every playId is in plays"
    ) |>
    pointblank::specially(
      fn = function(x) {
        ids <- unique(x$athleteId)
        !length(ids) || mean(ids %in% roster$playerId) >= min_roster_share
      },
      label = "athleteId is in the roster namespace"
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "play_stats", stop_on_fail)
}

#' Data contract for the player x game table
#'
#' Guards [build_player_game()] (decision 0035). Enforces the key
#' `(playerId, gameId)`, that every `gameId` is a real game, and no silent row
#' loss: the output has exactly one row per distinct `(playerId, gameId)` in
#' `game_player_stats`. Elo is allowed to be `NA` (FCS and lower-division
#' opponents have none), so its share is reported by the audit row rather than
#' failed here. Usage counts are non-negative where present.
#'
#' @param player_game Output of [build_player_game()].
#' @param game_player_stats Cleaned long player-game stats (the input).
#' @param games Cleaned games (the game-id reference set).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_player_game <- function(
  player_game,
  game_player_stats,
  games,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  n_expected <- dplyr::n_distinct(game_player_stats[c("playerId", "gameId")])
  # Yardage is signed (sacks and rushing losses are negative), so it gets a
  # range check instead of the non-negative count check.
  yard_stat_cols <- c("pass_yds", "rush_yds", "rec_yds")
  count_stat_cols <- c(
    "pass_cmp",
    "pass_att",
    "pass_td",
    "pass_int",
    "rush_car",
    "rush_td",
    "rec",
    "rec_td",
    "tackles",
    "solo_tackles",
    "tfl",
    "sacks"
  )
  stat_cols <- c(count_stat_cols, yard_stat_cols)
  agent <- pointblank::create_agent(player_game, label = "player_game") |>
    pointblank::col_exists(c(
      "playerId",
      "gameId",
      "season",
      "week",
      "seasonType",
      "team",
      "team_conference",
      "opponent",
      "opponent_conference",
      "home_away",
      "neutral_site",
      "team_points",
      "opponent_points",
      "team_pregame_elo",
      "opponent_pregame_elo",
      "team_games",
      dplyr::all_of(stat_cols)
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(
      playerId,
      gameId,
      season,
      week,
      seasonType,
      team,
      opponent,
      home_away,
      neutral_site,
      team_games
    )) |>
    pointblank::rows_distinct(pointblank::vars(playerId, gameId)) |>
    # No silent row loss: one row per distinct (playerId, gameId) in the input.
    pointblank::col_vals_equal(
      "n",
      n_expected,
      preconditions = function(x) tibble::tibble(n = nrow(x))
    ) |>
    pointblank::col_vals_in_set("gameId", set = unique(games$id)) |>
    pointblank::col_vals_between("season", 2010L, 2026L) |>
    pointblank::col_vals_gte("week", 1L) |>
    pointblank::col_vals_in_set("home_away", set = c("home", "away")) |>
    pointblank::col_vals_expr(rlang::expr(opponent != team)) |>
    pointblank::col_vals_between("team_games", 1L, 20L) |>
    pointblank::col_vals_gte("team_points", 0L, na_pass = TRUE) |>
    pointblank::col_vals_gte("opponent_points", 0L, na_pass = TRUE) |>
    pointblank::col_vals_between(
      "team_pregame_elo",
      500,
      3000,
      na_pass = TRUE
    ) |>
    pointblank::col_vals_between(
      "opponent_pregame_elo",
      500,
      3000,
      na_pass = TRUE
    )
  # Usage counts are non-negative where present; NA means no line in that
  # category for the player-game (see build_player_game()). Yards are bounded
  # loosely (a single game's passing or rushing yards stay well inside this).
  agent <- agent |>
    pointblank::col_vals_gte(
      columns = dplyr::all_of(count_stat_cols),
      value = 0,
      na_pass = TRUE
    ) |>
    pointblank::col_vals_between(
      columns = dplyr::all_of(yard_stat_cols),
      left = -200,
      right = 1000,
      na_pass = TRUE
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "player_game", stop_on_fail)
}

#' Data contract for the season-arc table
#'
#' Guards [build_season_arcs()]. Enforces the key `(playerId, season, category,
#' statType)` and no silent row loss: the output has exactly one row per
#' player-season that has a numeric value for each headline stat in
#' `player_stats`. Yardage and tackle totals are bounded loosely, and every
#' `season_index` is at least 1.
#'
#' @param season_arc Output of [build_season_arcs()].
#' @param player_stats Cleaned long player stats (the input).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_season_arc <- function(season_arc, player_stats, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  keys <- season_arc_stat_map
  expected <- player_stats |>
    dplyr::semi_join(keys, by = c("category", "statType")) |>
    dplyr::mutate(value = suppressWarnings(as.numeric(.data$stat))) |>
    dplyr::filter(!is.na(.data$value)) |>
    dplyr::distinct(
      .data$playerId,
      .data$season,
      .data$category,
      .data$statType
    ) |>
    nrow()
  agent <- pointblank::create_agent(season_arc, label = "season_arc") |>
    pointblank::col_exists(c(
      "playerId",
      "player",
      "season",
      "season_index",
      "team",
      "category",
      "statType",
      "value"
    )) |>
    pointblank::rows_distinct(pointblank::vars(
      playerId,
      season,
      category,
      statType
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(
      playerId,
      season,
      season_index,
      category,
      statType,
      value
    )) |>
    # No silent row loss: one row per numeric player-season-stat in the input.
    pointblank::col_vals_equal(
      "n",
      expected,
      preconditions = function(x) tibble::tibble(n = nrow(x))
    ) |>
    pointblank::col_vals_between("season", 2010L, 2026L) |>
    pointblank::col_vals_gte("season_index", 1L) |>
    pointblank::col_vals_between("value", -500, 6000) |>
    pointblank::interrogate()
  enforce_contract(agent, "season_arc", stop_on_fail)
}

#' Data contract for the opponent-adjusted game-production table
#'
#' Guards [build_game_production()] (decision 0037). Enforces the key
#' `(playerId, gameId, stat)` and no silent row loss: one row per non-`NA`
#' yardage value in `player_game`. Every opponent Elo band is one of the
#' declared bands (`"Unrated"` included, never dropped), and every residual is
#' a finite number.
#'
#' @param game_production Output of [build_game_production()].
#' @param player_game Output of [build_player_game()] (the input).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_game_production <- function(
  game_production,
  player_game,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  n_expected <- sum(
    !is.na(
      player_game[game_production_stat_cols]
    )
  )
  agent <- pointblank::create_agent(
    game_production,
    label = "game_production"
  ) |>
    pointblank::col_exists(c(
      "playerId",
      "gameId",
      "season",
      "week",
      "team",
      "opponent",
      "opponent_elo_band",
      "stat",
      "value",
      "baseline",
      "band_n",
      "residual"
    )) |>
    pointblank::rows_distinct(pointblank::vars(playerId, gameId, stat)) |>
    # No silent row loss: one row per non-NA yardage value in player_game.
    pointblank::col_vals_equal(
      "n",
      n_expected,
      preconditions = function(x) tibble::tibble(n = nrow(x))
    ) |>
    pointblank::col_vals_not_null(pointblank::vars(
      playerId,
      gameId,
      season,
      team,
      opponent,
      opponent_elo_band,
      stat,
      value,
      baseline,
      residual
    )) |>
    pointblank::col_vals_in_set(
      "opponent_elo_band",
      set = opponent_elo_band_levels
    ) |>
    pointblank::col_vals_in_set("stat", set = game_production_stat_cols) |>
    pointblank::col_vals_in_set("gameId", set = unique(player_game$gameId)) |>
    pointblank::col_vals_between("season", 2010L, 2026L) |>
    pointblank::col_vals_gte("band_n", 1L) |>
    pointblank::col_vals_between("residual", -1e6, 1e6) |>
    pointblank::interrogate()
  enforce_contract(agent, "game_production", stop_on_fail)
}

#' Data contract for the player usage table
#'
#' Guards [build_player_usage()] (issue #50, decision 0038). Enforces the key
#' `(playerId, season, team)`; `games_appeared <= team_games` (the requirement
#' issue #51 depends on); the same bounds for the regular-season columns; and
#' no silent row loss on either join: the games-appeared counts sum to the
#' player-game rows, and each team-season's `team_games` equals
#' [team_record()]'s `games_played`. Appearance rates are not failed on a
#' low value: no stat line does not mean the player did not play (offensive
#' linemen and special teams rarely log one), so that caveat lives in the
#' post, not in the contract.
#'
#' @param player_usage Output of [build_player_usage()].
#' @param player_game Output of [build_player_game()] (the input).
#' @param games Cleaned games (the team-game reference set).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_player_usage <- function(
  player_usage,
  player_game,
  games,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  n_expected <- nrow(player_game)
  # Tie-out: each team-season's team_games (the schedule count) must equal the
  # games_played that team_record() reports for the same season and team.
  rec <- team_record(games) |>
    dplyr::select("season", "team", rec_games = "games_played")
  team_seasons <- player_usage |>
    dplyr::distinct(.data$season, .data$team, .data$team_games) |>
    dplyr::inner_join(rec, by = c("season", "team"))
  n_team_mismatch <- sum(team_seasons$team_games != team_seasons$rec_games)

  agent <- pointblank::create_agent(player_usage, label = "player_usage") |>
    pointblank::col_exists(c(
      "playerId",
      "season",
      "team",
      "position_group",
      "class_year",
      "on_roster",
      "team_games",
      "games_appeared",
      "appearance_rate",
      "reg_team_games",
      "reg_games_appeared",
      "reg_appearance_rate",
      "pass_att_pg",
      "rush_car_pg",
      "rec_pg",
      "tackles_pg"
    )) |>
    pointblank::rows_distinct(pointblank::vars(playerId, season, team)) |>
    pointblank::col_vals_not_null(pointblank::vars(
      playerId,
      season,
      team,
      on_roster,
      team_games,
      games_appeared,
      reg_team_games,
      reg_games_appeared
    )) |>
    pointblank::col_vals_between("season", 2010L, 2026L) |>
    pointblank::col_vals_gte("team_games", 0L) |>
    pointblank::col_vals_gte("games_appeared", 0L) |>
    pointblank::col_vals_expr(rlang::expr(games_appeared <= team_games)) |>
    pointblank::col_vals_expr(rlang::expr(
      reg_games_appeared <= reg_team_games
    )) |>
    pointblank::col_vals_expr(rlang::expr(reg_team_games <= team_games)) |>
    pointblank::col_vals_between(
      "appearance_rate",
      0,
      1,
      na_pass = TRUE
    ) |>
    # NA is allowed: a stat-line-only player-season has no roster position.
    pointblank::col_vals_in_set(
      "position_group",
      set = c(harmonized_position_levels(), NA_character_)
    ) |>
    pointblank::col_vals_between(
      "class_year",
      1L,
      5L,
      na_pass = TRUE
    ) |>
    # No silent row loss: every player-game row is counted once.
    pointblank::col_vals_equal(
      "n",
      n_expected,
      preconditions = function(x) {
        tibble::tibble(n = sum(x$games_appeared))
      }
    ) |>
    # Team-game tie-out with team_record(): zero mismatched team-seasons.
    pointblank::col_vals_equal(
      "n",
      0L,
      preconditions = function(x) tibble::tibble(n = n_team_mismatch)
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "player_usage", stop_on_fail)
}

# ---- person-period outcome table (decision 0032) ---------------------------

#' Contract for the person-period outcome table
#'
#' Validates `build_outcomes()` output: the modeling labels must preserve the
#' population grain (no silent join loss), the drafted/UDFA events must stay
#' mutually exclusive, `nfl_entry` must equal the union of its components, and
#' administrative right-censoring must carry `NA` outcomes — never a fabricated
#' 0.
#'
#' @param outcomes Person-period outcome table (see [build_outcomes()]).
#' @param ps_pop Model population the table was built from; its
#'   `(playerId, season)` row count is the expected row count.
#' @param stop_on_fail Abort on failure? `FALSE` records the result for the
#'   audit log instead (the `ok_*` target pattern).
#'
#' @return The interrogated pointblank agent (invisible).
#' @export
contract_outcomes <- function(outcomes, ps_pop, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  expected <- nrow(dplyr::distinct(ps_pop, .data$playerId, .data$season))
  agent <- pointblank::create_agent(outcomes, label = "outcomes") |>
    pointblank::col_vals_not_null(
      pointblank::vars(
        playerId,
        season,
        draft_year,
        hs_grad_year,
        draft_eligible,
        outcome_observed_d
      )
    ) |>
    pointblank::col_vals_equal(
      pointblank::vars(n),
      expected,
      preconditions = function(x) {
        dplyr::mutate(x, n = nrow(x))
      }
    ) |>
    pointblank::rows_distinct(pointblank::vars(playerId, season)) |>
    pointblank::col_vals_expr(rlang::expr(
      draft_eligible == (.data$years_since_hs >= .data$min_years_since_hs)
    )) |>
    pointblank::col_vals_expr(rlang::expr(
      !(dplyr::coalesce(.data$outcome_drafted_d, FALSE) &
        dplyr::coalesce(.data$outcome_signed_udfa_d, FALSE))
    )) |>
    pointblank::col_vals_expr(rlang::expr(
      dplyr::coalesce(.data$outcome_nfl_entry_d, FALSE) ==
        (dplyr::coalesce(.data$outcome_drafted_d, FALSE) |
          dplyr::coalesce(.data$outcome_signed_udfa_d, FALSE))
    )) |>
    pointblank::col_vals_expr(rlang::expr(
      .data$outcome_observed_d | is.na(.data$outcome_drafted_d)
    )) |>
    # Censoring is the ONLY source of NA in the UDFA flag: an observed
    # undrafted player with no roster match is 0, not NA (the left-join
    # artifact this guards against makes naive prevalence denominators wrong).
    pointblank::col_vals_expr(rlang::expr(
      !.data$outcome_observed_d | !is.na(.data$outcome_signed_udfa_d)
    )) |>
    pointblank::col_vals_not_null(
      pointblank::vars(outcome_draft_round_d, outcome_draft_pick_d),
      preconditions = function(x) {
        dplyr::filter(x, .data$outcome_drafted_d %in% TRUE)
      }
    ) |>
    pointblank::col_vals_expr(rlang::expr(
      (.data$outcome_nfl_entry_d %in% TRUE) ==
        !is.na(
          .data$outcome_made_roster_entry_year
        )
    )) |>
    pointblank::col_vals_gt(
      pointblank::vars(t),
      0,
      preconditions = function(x) {
        dplyr::transmute(x, t = .data$years_to_nfl_entry)
      }
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "outcomes", stop_on_fail)
}

#' Data contract for pick-level coach links
#'
#' Asserts [link_coaches_picks()] produced a valid pick x coach table: unique
#' `(year, overall, coach_id)` key, every linked coach-season exists in the
#' coaches table, every crediting roster season is before the draft year, and
#' under the `last` rule each pick's `season` is that pick's **maximum**
#' roster season. Also asserts the link is not silently empty relative to the
#' eligible pick population (coverage floor guards against a broken join).
#'
#' @param linked Pick-coach links from [link_coaches_picks()].
#' @param picks Cleaned picks (same input as the link).
#' @param roster Roster backbone (same input as the link).
#' @param coaches Cleaned coach-seasons (same input as the link).
#' @param rule Attribution rule used.
#' @param draft_year_min Draft-year floor used by the link.
#' @param min_coverage Minimum share of eligible picks that must appear with
#'   at least one coach (guards silent join loss).
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_coaches_picks <- function(
  linked,
  picks,
  roster,
  coaches,
  rule = c("last", "any"),
  draft_year_min = 2011L,
  min_coverage = 0.9,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  rule <- rlang::arg_match(rule)
  eligible <- picks |>
    dplyr::filter(!is.na(.data$playerId), .data$year >= .env$draft_year_min) |>
    dplyr::distinct(.data$year, .data$overall)
  covered <- dplyr::distinct(linked, .data$year, .data$overall)
  coverage <- nrow(covered) / nrow(eligible)

  # expected seasons pool per pick: what the link should have joined against
  pool <- picks |>
    dplyr::filter(!is.na(.data$playerId), .data$year >= .env$draft_year_min) |>
    dplyr::distinct(.data$playerId, .data$year, .data$overall) |>
    dplyr::inner_join(
      dplyr::distinct(roster, .data$playerId, .data$season, .data$team),
      by = "playerId",
      relationship = "many-to-many"
    ) |>
    dplyr::filter(.data$season < .data$year)

  agent <- pointblank::create_agent(linked, label = "coaches_picks") |>
    pointblank::col_exists(c(
      "year",
      "overall",
      "position",
      "name",
      "playerId",
      "team",
      "season",
      "coach_id",
      "coach_name"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(year, overall, coach_id)) |>
    pointblank::col_vals_not_null(pointblank::vars(season)) |>
    pointblank::col_vals_equal(
      "n",
      nrow(dplyr::distinct(linked, .data$year, .data$overall, .data$coach_id)),
      preconditions = function(x) dplyr::mutate(x, n = nrow(x))
    ) |>
    pointblank::interrogate()
  # referential checks pointblank can't express against another table; run as
  # hard assertions alongside the agent.
  ok_ref <- all(linked$season < linked$year) &&
    all(linked$season %in% coaches$season) &&
    all(
      paste(linked$team, linked$season, linked$coach_id) %in%
        paste(coaches$school, coaches$season, coaches$coach_id)
    )
  ok_rule <- if (rule == "last") {
    expected_last <- pool |>
      dplyr::group_by(.data$year, .data$overall) |>
      dplyr::summarise(max_season = max(.data$season), .groups = "drop")
    nrow(dplyr::anti_join(
      linked,
      expected_last |> dplyr::rename(season = "max_season"),
      by = c("year", "overall", "season")
    )) ==
      0L
  } else {
    nrow(dplyr::anti_join(linked, pool, by = c("year", "overall", "season"))) ==
      0L
  }
  ok_cov <- coverage >= min_coverage
  ok <- ok_ref && ok_rule && ok_cov
  if (!ok && stop_on_fail) {
    stop(sprintf(
      "coaches_picks contract failed: referential=%s, rule=%s, coverage=%.3f",
      ok_ref,
      ok_rule,
      coverage
    ))
  }
  invisible(agent)
}

#' Season coverage of the season-keyed published tables (decision 0034)
#'
#' A season-scoped refresh rewrites only the selected seasons, so this checks
#' that no season silently went missing: every season from `min_season`
#' through the last completed one must have rows in each table. The current
#' season (or incoming recruiting class) may still be empty early in its cycle,
#' so it is not required.
#'
#' @param seasons_by_table Named list; each element is the season column of
#'   one table (e.g. `list(roster = roster$season)`).
#' @param required Named list of required season vectors, same names.
#' @param stop_on_fail Abort on failure.
#' @return The pointblank agent, invisibly.
#' @export
contract_season_coverage <- function(
  seasons_by_table,
  required,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  tbl <- tibble::tibble(
    table = names(seasons_by_table),
    n_missing = vapply(
      names(seasons_by_table),
      function(t) {
        length(setdiff(required[[t]], unique(seasons_by_table[[t]])))
      },
      integer(1)
    )
  )
  agent <- pointblank::create_agent(tbl, label = "season_coverage") |>
    pointblank::col_vals_equal("n_missing", 0L) |>
    pointblank::interrogate()
  enforce_contract(agent, "season_coverage", stop_on_fail)
}

#' Seasons each season-keyed table must contain
#'
#' `min_season` through the season before each source's current one
#' ([refresh_season_for()]): the last completed season for college data, the
#' current season's signed class for recruiting.
#'
#' @param sources Season-keyed source names.
#' @param min_season The earliest season in the window.
#' @param date The date the window is evaluated at.
#' @return A named list of integer season vectors.
#' @keywords internal
required_seasons <- function(sources, min_season = 2010L, date = Sys.Date()) {
  stats::setNames(
    lapply(sources, function(s) {
      seq.int(min_season, refresh_season_for(s, date) - 1L)
    }),
    sources
  )
}

#' Data contract for the explorer shell assets
#'
#' Guards the first-view assets of the explorer (plans/explorer.md): one row
#' per `(team_id, season)` with a record that adds up; no silent loss (the
#' team-seasons' games equal the FBS/FCS sides of completed, scored games);
#' every team-season has a display row with a color, and teams playing in the
#' default season also a logo (defunct programs like Jacksonville may lack
#' one); every team-season has a tier; Elo on every
#' FBS team-season from 2022 on (coverage is ~100% there); `meta` agrees with
#' the games and names only documented tables; and the gzipped first view fits
#' the budget (decision 0046).
#'
#' @param teams Output of [build_explorer_teams()].
#' @param team_season Output of [build_explorer_team_season()].
#' @param meta Output of [build_explorer_meta()].
#' @param games Cleaned games.
#' @param max_gzip_bytes First-view budget in gzipped bytes.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_explorer_shell <- function(
  teams,
  team_season,
  meta,
  games,
  max_gzip_bytes = 250000L,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  expected_games <- explorer_game_sides(games) |>
    dplyr::filter(
      .data$classification %in% c("fbs", "fcs"),
      !is.na(.data$points),
      !is.na(.data$opp_points)
    ) |>
    nrow()
  has_color <- teams$team_id[!is.na(teams$color)]
  current_ids <- unique(
    team_season$team_id[team_season$season == meta$default_season]
  )
  has_logo <- teams$team_id[!is.na(teams$logo)]
  dicts <- sub("\\.yml$", "", list.files(app_sys("dict"), "\\.yml$"))
  gzip_bytes <- sum(vapply(
    list(meta, teams, team_season),
    explorer_json_gzip_bytes,
    integer(1)
  ))
  check <- function(agent, ok) {
    pointblank::col_vals_equal(
      agent,
      "ok",
      TRUE,
      preconditions = function(x) tibble::tibble(ok = ok)
    )
  }
  agent <- pointblank::create_agent(team_season, label = "explorer_shell") |>
    pointblank::col_exists(c(
      "team_id",
      "season",
      "conference",
      "classification",
      "tier",
      "games",
      "wins",
      "losses",
      "ties",
      "elo_end",
      "win_pct"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(team_id, season, tier)) |>
    pointblank::rows_distinct(pointblank::vars(team_id, season)) |>
    pointblank::col_vals_expr(rlang::expr(
      wins + losses + ties == games
    )) |>
    pointblank::col_vals_gt("games", 0L) |>
    pointblank::col_vals_between("win_pct", 0, 1) |>
    pointblank::col_vals_lte("season", meta$default_season) |>
    pointblank::col_vals_not_null(
      pointblank::vars(elo_end),
      preconditions = function(x) {
        dplyr::filter(x, .data$classification == "fbs", .data$season >= 2022L)
      }
    ) |>
    check(nrow(team_season) > 0L) |>
    check(sum(team_season$games) == expected_games) |>
    check(all(team_season$team_id %in% has_color)) |>
    check(all(current_ids %in% has_logo)) |>
    check(identical(meta$default_season, explorer_default_season(games))) |>
    # The page falls back to the default team and season when the hash names
    # an unknown one, so both must exist; the season menu is contiguous.
    check(meta$default_team %in% teams$team_id) |>
    check(identical(
      meta$seasons,
      seq.int(min(meta$seasons), meta$default_season)
    )) |>
    check(all(unlist(meta$sources) %in% dicts)) |>
    check(gzip_bytes <= max_gzip_bytes) |>
    pointblank::interrogate()
  enforce_contract(agent, "explorer_shell", stop_on_fail)
}

#' Data contract for the explorer team-games table
#'
#' Guards [build_explorer_team_games()]: one row per `(team_id, game_id)`; no
#' loss against the team-season records; a result that matches the score;
#' win probabilities in 0 to 1; an Elo change that equals post minus pre; and
#' the largest season's gzipped JSON within the first-view budget (decision
#' 0046), so the page's first load stays small as seasons accumulate.
#'
#' @param team_games Output of [build_explorer_team_games()].
#' @param team_season Output of [build_explorer_team_season()].
#' @param max_gzip_bytes Largest allowed gzipped size of one season's file.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_explorer_team_games <- function(
  team_games,
  team_season,
  max_gzip_bytes = 150000L,
  stop_on_fail = TRUE
) {
  season_bytes <- vapply(
    split(team_games, team_games$season),
    explorer_json_gzip_bytes,
    integer(1)
  )
  rlang::check_installed("pointblank")
  check <- function(agent, ok) {
    pointblank::col_vals_equal(
      agent,
      "ok",
      TRUE,
      preconditions = function(x) tibble::tibble(ok = ok)
    )
  }
  agent <- pointblank::create_agent(
    team_games,
    label = "explorer_team_games"
  ) |>
    pointblank::col_vals_not_null(pointblank::vars(
      team_id,
      game_id,
      season,
      result
    )) |>
    pointblank::rows_distinct(pointblank::vars(team_id, game_id)) |>
    pointblank::col_vals_in_set("result", c("W", "L", "T")) |>
    pointblank::col_vals_expr(rlang::expr(
      (result == "W") == (points > opp_points) &
        (result == "L") == (points < opp_points)
    )) |>
    pointblank::col_vals_between("wp_pre", 0, 1, na_pass = TRUE) |>
    pointblank::col_vals_between("wp_post", 0, 1, na_pass = TRUE) |>
    pointblank::col_vals_expr(
      rlang::expr(abs(elo_delta - (elo_post - elo_pre)) <= 1L),
      preconditions = function(x) {
        dplyr::filter(x, !is.na(.data$elo_pre), !is.na(.data$elo_post))
      }
    ) |>
    check(nrow(team_games) > 0L) |>
    check(nrow(team_games) == sum(team_season$games)) |>
    check(max(c(0L, season_bytes)) <= max_gzip_bytes) |>
    pointblank::interrogate()
  enforce_contract(agent, "explorer_team_games", stop_on_fail)
}

#' Data contract for the explorer plays table
#'
#' Guards [build_explorer_plays()]: one row per input play (no loss); every
#' play's game is in `games`; the margin equals the home score minus the away
#' score; cumulative PPA is never missing; and at least 99.9% of plays have an
#' elapsed time (the rest have a missing clock). Plays whose period the cleaner
#' nulled (CFBD period 0, 37 plays in 2010-2013) are kept with no elapsed time.
#'
#' @param explorer_plays Output of [build_explorer_plays()].
#' @param plays Cleaned plays.
#' @param games Cleaned games.
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_explorer_plays <- function(
  explorer_plays,
  plays,
  games,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  check <- function(agent, ok) {
    pointblank::col_vals_equal(
      agent,
      "ok",
      TRUE,
      preconditions = function(x) tibble::tibble(ok = ok)
    )
  }
  agent <- pointblank::create_agent(explorer_plays, label = "explorer_plays") |>
    pointblank::col_vals_not_null(pointblank::vars(
      game_id,
      play_id,
      home_cum_ppa
    )) |>
    pointblank::rows_distinct(pointblank::vars(play_id)) |>
    pointblank::col_vals_expr(rlang::expr(
      home_margin == home_score - away_score
    )) |>
    pointblank::col_vals_gte("elapsed", 0L, na_pass = TRUE) |>
    check(nrow(explorer_plays) == nrow(plays)) |>
    check(all(explorer_plays$game_id %in% games$id)) |>
    check(mean(!is.na(explorer_plays$elapsed)) >= 0.999) |>
    check(
      !any(
        explorer_plays |>
          dplyr::filter(!is.na(.data$elapsed)) |>
          dplyr::summarise(
            back = any(diff(.data$elapsed) < 0),
            .by = "game_id"
          ) |>
          dplyr::pull("back")
      )
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "explorer_plays", stop_on_fail)
}

#' Data contract for the explorer per-game plays files
#'
#' Guards the directory [write_explorer_plays()] writes: exactly one
#' `plays/<season>/<game_id>.parquet` per game in `explorer_plays`, and no
#' other files. A missing game would blank the timeline; a stray file would
#' be served as if it were a game.
#'
#' @param plays_dir The `plays/` directory.
#' @param explorer_plays Output of [build_explorer_plays()].
#' @param stop_on_fail Abort on failure (default `TRUE`)?
#' @return The interrogated pointblank agent, invisibly.
#' @export
contract_explorer_plays_files <- function(
  plays_dir,
  explorer_plays,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  games <- dplyr::distinct(explorer_plays, .data$season, .data$game_id)
  expected <- file.path(
    "plays",
    games$season,
    paste0(games$game_id, ".parquet")
  )
  found <- if (dir.exists(plays_dir)) {
    file.path(
      "plays",
      list.files(plays_dir, recursive = TRUE)
    )
  } else {
    character()
  }
  counts <- tibble::tibble(
    count_diff = length(found) - nrow(games),
    missing = sum(!expected %in% found),
    extra = sum(!found %in% expected),
    dir_exists = dir.exists(plays_dir)
  )
  agent <- pointblank::create_agent(counts, label = "explorer_plays_files") |>
    pointblank::col_vals_equal("dir_exists", TRUE) |>
    pointblank::col_vals_equal("count_diff", 0L) |>
    pointblank::col_vals_equal("missing", 0L) |>
    pointblank::col_vals_equal("extra", 0L) |>
    pointblank::interrogate()
  enforce_contract(agent, "explorer_plays_files", stop_on_fail)
}
