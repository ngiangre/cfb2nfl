# Position harmonization across the four player-position vocabularies (issue
# #49): recruiting (247-style codes), CFBD roster / picks (roster codes and
# long-form names), and nflverse draft picks / rosters (PFR-style codes).
# One code table, so a post or contract that groups positions cannot disagree
# with another about what "EDGE" or "IOL" means.

#' Harmonized position groups, in display order
#'
#' Shared by every harmonized position table. "Athlete" is its own category
#' because a recruit or college player listed as ATH has no position group to
#' transfer from; "Position not recorded" covers blanks and CFBD's `?`.
#'
#' @return A character vector of the eleven group labels.
#' @export
harmonized_position_levels <- function() {
  c(
    "Quarterback",
    "Running back",
    "Receiver",
    "Tight end",
    "Offensive line",
    "Defensive line",
    "Linebacker",
    "Defensive back",
    "Special teams",
    "Athlete",
    "Position not recorded"
  )
}

#' Feeds whose position vocabularies are harmonized
#'
#' @return The five source names accepted by [harmonize_position()].
#' @export
position_sources <- function() {
  c("recruiting", "roster", "picks", "nfl_draft", "nfl_roster")
}

# Raw code (or long-form name) -> harmonized group. Built from every value
# observed in the five feeds (see `unmapped_positions()`); a new raw value
# that is not listed here is reported by the contract, never silently grouped.
position_code_map <- function() {
  quarterback <- c("QB", "PRO", "DUAL", "Quarterback")
  running_back <- c("RB", "FB", "APB", "Running Back", "Fullback")
  receiver <- c("WR", "Wide Receiver")
  tight_end <- c("TE", "Tight End")
  offensive_line <- c(
    "OL",
    "OT",
    "T",
    "G",
    "OG",
    "C",
    "OC",
    "IOL",
    "Offensive Tackle",
    "Offensive Guard",
    "Center"
  )
  defensive_line <- c(
    "DL",
    "DE",
    "DT",
    "NT",
    "EDGE",
    "SDE",
    "WDE",
    "Defensive End",
    "Defensive Tackle",
    "Defensive Edge"
  )
  linebacker <- c(
    "LB",
    "ILB",
    "OLB",
    "MLB",
    "Linebacker",
    "Inside Linebacker",
    "Outside Linebacker"
  )
  defensive_back <- c(
    "DB",
    "CB",
    "S",
    "SS",
    "FS",
    "SAF",
    "Defensive Back",
    "Cornerback",
    "Safety"
  )
  special_teams <- c(
    "K",
    "PK",
    "P",
    "LS",
    "PR",
    "KR",
    "Place Kicker",
    "Punter",
    "Long Snapper",
    "Kick Returner"
  )
  c(
    setNames(rep("Quarterback", length(quarterback)), quarterback),
    setNames(rep("Running back", length(running_back)), running_back),
    setNames(rep("Receiver", length(receiver)), receiver),
    setNames(rep("Tight end", length(tight_end)), tight_end),
    setNames(rep("Offensive line", length(offensive_line)), offensive_line),
    setNames(rep("Defensive line", length(defensive_line)), defensive_line),
    setNames(rep("Linebacker", length(linebacker)), linebacker),
    setNames(rep("Defensive back", length(defensive_back)), defensive_back),
    setNames(rep("Special teams", length(special_teams)), special_teams),
    ATH = "Athlete",
    `?` = "Position not recorded"
  )
}

#' Harmonize a raw position value into a shared position group
#'
#' Blank (`NA`) positions become "Position not recorded"; a raw value with no
#' mapping returns `NA` so callers and the contract can see it. `source` names
#' the feed the value came from and is validated, so a typo cannot silently
#' select the wrong vocabulary.
#'
#' @param position Character vector of raw position codes.
#' @param source One of [position_sources()].
#' @return Character vector of harmonized group labels (see
#'   [harmonized_position_levels()]); `NA` only for unmapped raw values.
#' @export
harmonize_position <- function(position, source) {
  source <- match.arg(source, position_sources())
  map <- position_code_map()
  position <- as.character(position)
  out <- unname(map[position])
  out[is.na(position)] <- "Position not recorded"
  out
}

#' Raw position values that the harmonization map does not cover
#'
#' The mapping-completeness check: every distinct non-blank raw value in each
#' feed must be listed in the code map.
#'
#' @param position Character vector of raw position codes from one feed.
#' @param source One of [position_sources()].
#' @return Character vector of unmapped raw values (empty when complete).
#' @export
unmapped_positions <- function(position, source) {
  source <- match.arg(source, position_sources())
  raw <- unique(stats::na.omit(as.character(position)))
  raw[is.na(harmonize_position(raw, source))]
}

#' Build the per-player position path (HS -> college -> NFL)
#'
#' One row per college athlete id (decision 0021 recipe), chaining the three
#' harmonized positions:
#' - **HS** is taken only through [link_recruiting()] (name-guarded, decision
#'   0013); a recruit whose name does not agree with the college name gets no
#'   HS group. The college name is the stat-line name where one exists, else
#'   the draft-listed name; players with neither cannot be guarded and stay
#'   unlinked.
#' - **College** groups come from the roster position in each season, ignoring
#'   blanks. The first, last, and modal (most seasons, then most recent) groups
#'   are kept, plus a flag for any in-college change of group.
#' - **NFL** is the nflverse draft position of the slot-linked pick
#'   (decision 0014). A player with more than one CFBD pick (id reuse,
#'   decision 0022) is not linked.
#'
#' Reused athlete ids are excluded from the universe (decision 0022).
#'
#' @param roster Cleaned roster (`playerId`, `season`, `position`).
#' @param recruiting Cleaned recruiting table (one row per `playerId`).
#' @param player_season Player-season backbone; supplies the college name.
#' @param picks_nfl Output of [link_nfl_draft()] (`playerId`, `gsis_id`,
#'   `nfl_matched`, `name`).
#' @param nfl_draft_picks Cleaned nflverse draft picks (`gsis_id`, `position`).
#' @param reused Athlete ids to exclude (see [reused_ids()]).
#' @return A tibble, one row per athlete id.
#' @export
build_position_path <- function(
  roster,
  recruiting,
  player_season,
  picks_nfl,
  nfl_draft_picks,
  reused = character()
) {
  universe <- roster |>
    dplyr::filter(!is.na(.data$playerId), !.data$playerId %in% reused) |>
    dplyr::distinct(.data$playerId)

  names_tbl <- dplyr::bind_rows(
    player_season |>
      dplyr::transmute(playerId = .data$playerId, player = .data$player),
    picks_nfl |>
      dplyr::filter(!is.na(.data$playerId)) |>
      dplyr::transmute(playerId = .data$playerId, player = .data$name)
  ) |>
    dplyr::filter(!is.na(.data$player)) |>
    dplyr::distinct(.data$playerId, .keep_all = TRUE)

  # HS: the guarded link decides which recruit row is trusted; the position
  # is read from that same recruit only when the guard passes.
  hs_pos <- recruiting |>
    dplyr::transmute(
      playerId = .data$playerId,
      recruit_position = .data$recruit_position
    )
  hs <- universe |>
    dplyr::left_join(names_tbl, by = "playerId") |>
    link_recruiting(recruiting) |>
    dplyr::mutate(hs_linked = dplyr::coalesce(.data$recruit_matched, FALSE)) |>
    dplyr::select("playerId", "hs_linked", "hs_class") |>
    dplyr::left_join(hs_pos, by = "playerId") |>
    dplyr::mutate(
      hs_group = dplyr::if_else(
        .data$hs_linked,
        harmonize_position(.data$recruit_position, "recruiting"),
        NA_character_
      )
    ) |>
    dplyr::select("playerId", "hs_linked", "hs_class", "hs_group")

  # College: recorded roster positions only, one row per player-season-group.
  college_obs <- roster |>
    dplyr::semi_join(universe, by = "playerId") |>
    dplyr::transmute(
      playerId = .data$playerId,
      season = .data$season,
      group = harmonize_position(.data$position, "roster")
    ) |>
    dplyr::filter(.data$group != "Position not recorded") |>
    dplyr::distinct() |>
    dplyr::arrange(.data$playerId, .data$season, .data$group)

  first_grp <- college_obs |>
    dplyr::distinct(.data$playerId, .keep_all = TRUE) |>
    dplyr::select("playerId", college_first_group = "group")
  last_grp <- college_obs |>
    dplyr::arrange(.data$playerId, dplyr::desc(.data$season), .data$group) |>
    dplyr::distinct(.data$playerId, .keep_all = TRUE) |>
    dplyr::select("playerId", college_last_group = "group")
  modal_grp <- college_obs |>
    dplyr::group_by(.data$playerId, .data$group) |>
    dplyr::summarise(
      n_seasons = dplyr::n_distinct(.data$season),
      last_season = max(.data$season),
      .groups = "drop"
    ) |>
    dplyr::arrange(
      .data$playerId,
      dplyr::desc(.data$n_seasons),
      dplyr::desc(.data$last_season)
    ) |>
    dplyr::distinct(.data$playerId, .keep_all = TRUE) |>
    dplyr::select("playerId", college_modal_group = "group")
  college <- college_obs |>
    dplyr::group_by(.data$playerId) |>
    dplyr::summarise(
      college_seasons = dplyr::n_distinct(.data$season),
      college_groups = dplyr::n_distinct(.data$group),
      .groups = "drop"
    ) |>
    dplyr::left_join(first_grp, by = "playerId") |>
    dplyr::left_join(last_grp, by = "playerId") |>
    dplyr::left_join(modal_grp, by = "playerId")

  # NFL: one CFBD pick per id, slot-linked, then the nflverse draft position.
  # Null gsis ids are dropped from the lookup: dplyr matches NA to NA by
  # default, which would fan a null-id pick out to every null-id draftee.
  nfl_pos <- nfl_draft_picks |>
    dplyr::filter(!is.na(.data$gsis_id)) |>
    dplyr::transmute(gsis_id = .data$gsis_id, nfl_position = .data$position)
  nfl <- picks_nfl |>
    dplyr::filter(
      !is.na(.data$playerId),
      .data$playerId %in% universe$playerId
    ) |>
    dplyr::group_by(.data$playerId) |>
    dplyr::summarise(
      n_picks = dplyr::n(),
      gsis_id = dplyr::first(.data$gsis_id),
      nfl_matched = dplyr::first(.data$nfl_matched),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      drafted = TRUE,
      nfl_linked = .data$n_picks == 1L &
        dplyr::coalesce(.data$nfl_matched, FALSE)
    ) |>
    dplyr::left_join(nfl_pos, by = "gsis_id") |>
    dplyr::mutate(
      nfl_group = dplyr::if_else(
        .data$nfl_linked,
        harmonize_position(.data$nfl_position, "nfl_draft"),
        NA_character_
      )
    ) |>
    dplyr::select("playerId", "drafted", "nfl_linked", "nfl_group")

  universe |>
    dplyr::left_join(hs, by = "playerId") |>
    dplyr::left_join(college, by = "playerId") |>
    dplyr::left_join(nfl, by = "playerId") |>
    dplyr::mutate(
      hs_linked = dplyr::coalesce(.data$hs_linked, FALSE),
      college_seasons = dplyr::coalesce(.data$college_seasons, 0L),
      college_groups = dplyr::coalesce(.data$college_groups, 0L),
      college_changed = .data$college_groups > 1L,
      drafted = dplyr::coalesce(.data$drafted, FALSE),
      nfl_linked = dplyr::coalesce(.data$nfl_linked, FALSE)
    ) |>
    dplyr::select(
      "playerId",
      "hs_linked",
      "hs_class",
      "hs_group",
      "college_seasons",
      "college_groups",
      "college_first_group",
      "college_last_group",
      "college_modal_group",
      "college_changed",
      "drafted",
      "nfl_linked",
      "nfl_group"
    )
}

#' Contract: every observed raw position is mapped (issue #49)
#'
#' Each feed's distinct raw position values must all be listed in the shared
#' harmonization map (see [unmapped_positions()]). A new code in any feed
#' fails here rather than silently dropping out of the position groups.
#'
#' @param feeds Named list of raw position vectors, names from
#'   [position_sources()].
#' @param stop_on_fail Abort on failure.
#' @return The pointblank agent, invisibly.
#' @export
contract_position_mapping <- function(feeds, stop_on_fail = TRUE) {
  rlang::check_installed("pointblank")
  n_unmapped <- vapply(
    names(feeds),
    function(s) length(unmapped_positions(feeds[[s]], s)),
    integer(1)
  )
  tbl <- tibble::tibble(
    source = names(feeds),
    n_unmapped = as.integer(n_unmapped)
  )
  agent <- pointblank::create_agent(tbl, label = "position_mapping") |>
    pointblank::col_vals_equal("n_unmapped", 0L) |>
    pointblank::interrogate()
  enforce_contract(agent, "position_mapping", stop_on_fail)
}

#' Contract: the per-player position path (issue #49)
#'
#' Checks the derived `position_path` table: one row per non-reused college
#' athlete id (row count equals the roster universe, so no silent row loss),
#' harmonized groups drawn from the shared levels, the link flags agree with
#' the group they gate (an HS group only when the name guard passed; an NFL
#' group only for a slot-linked draftee), the change flag matches the group
#' count, and slot-link coverage of CFBD draftees meets a floor.
#'
#' @param position_path The derived table from [build_position_path()].
#' @param n_universe Expected row count: non-reused roster athlete ids.
#' @param n_picks_universe CFBD draft picks (2010+) whose id is in the
#'   universe and unique among picks.
#' @param min_nfl_coverage Floor on the slot-linked share of those picks
#'   (decision 0014 measured 99.7% in its spike; the 2010+ linked share is
#'   about 98.9%).
#' @param stop_on_fail Abort on failure.
#' @return The pointblank agent, invisibly.
#' @export
contract_position_path <- function(
  position_path,
  n_universe,
  n_picks_universe,
  min_nfl_coverage = 0.97,
  stop_on_fail = TRUE
) {
  rlang::check_installed("pointblank")
  levels <- harmonized_position_levels()
  n_nfl <- sum(position_path$nfl_linked, na.rm = TRUE)
  nfl_coverage <- if (n_picks_universe > 0) n_nfl / n_picks_universe else 1
  agent <- pointblank::create_agent(position_path, label = "position_path") |>
    pointblank::col_exists(c(
      "playerId",
      "hs_linked",
      "hs_class",
      "hs_group",
      "college_seasons",
      "college_groups",
      "college_first_group",
      "college_last_group",
      "college_modal_group",
      "college_changed",
      "drafted",
      "nfl_linked",
      "nfl_group"
    )) |>
    pointblank::col_vals_not_null(pointblank::vars(playerId)) |>
    pointblank::rows_distinct(pointblank::vars(playerId)) |>
    # Row floor and row count: an empty table must not pass vacuously, and
    # every universe id must be present (no silent row loss).
    pointblank::col_vals_gt(
      "n",
      0L,
      preconditions = function(x) tibble::tibble(n = nrow(x))
    ) |>
    pointblank::col_vals_equal(
      "n",
      as.integer(n_universe),
      preconditions = function(x) tibble::tibble(n = nrow(x))
    ) |>
    # Group columns are NA when a stage is unlinked or unrecorded; every
    # non-NA value must be a shared level (pointblank's col_vals_in_set() would
    # fail the NAs, so count the off-level values instead).
    pointblank::col_vals_equal(
      "n_off_level",
      0L,
      preconditions = function(x) {
        off <- function(v) sum(!is.na(v) & !v %in% levels)
        tibble::tibble(
          n_off_level = off(x$hs_group) +
            off(x$college_first_group) +
            off(x$college_last_group) +
            off(x$college_modal_group) +
            off(x$nfl_group)
        )
      }
    ) |>
    pointblank::col_vals_expr(rlang::expr(!hs_linked | !is.na(hs_group))) |>
    pointblank::col_vals_expr(rlang::expr(hs_linked | is.na(hs_group))) |>
    pointblank::col_vals_expr(
      rlang::expr(!nfl_linked | (drafted & !is.na(nfl_group)))
    ) |>
    pointblank::col_vals_expr(
      rlang::expr(college_changed == (college_groups > 1L))
    ) |>
    pointblank::col_vals_gte(
      "nfl_coverage",
      min_nfl_coverage,
      preconditions = function(x) {
        tibble::tibble(nfl_coverage = .env$nfl_coverage)
      }
    ) |>
    pointblank::interrogate()
  enforce_contract(agent, "position_path", stop_on_fail)
}

#' Expected sizes for the position-path contract
#'
#' The universe is the non-reused roster athlete ids. The coverage denominator
#' is 2010+ draft picks whose id is in that universe and is not shared by
#' another pick (an id shared by two picks is not slot-linked, decision 0022).
#'
#' @param roster Cleaned roster.
#' @param picks_nfl Output of [link_nfl_draft()].
#' @param reused Reused athlete ids (see [reused_ids()]).
#' @return A list with `n_universe` and `n_picks_universe`.
#' @export
position_universe_counts <- function(roster, picks_nfl, reused = character()) {
  ids <- unique(roster$playerId[
    !is.na(roster$playerId) & !roster$playerId %in% reused
  ])
  shared <- picks_nfl$playerId[
    !is.na(picks_nfl$playerId) & duplicated(picks_nfl$playerId)
  ]
  in_universe <- !is.na(picks_nfl$playerId) &
    picks_nfl$playerId %in% ids &
    !picks_nfl$playerId %in% shared &
    picks_nfl$year >= 2010L
  list(
    n_universe = length(ids),
    n_picks_universe = sum(in_universe)
  )
}
