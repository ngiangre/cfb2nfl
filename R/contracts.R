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
    pointblank::interrogate()
  enforce_contract(agent, "game_player_stats", stop_on_fail)
}
