#' Conference tier levels
#'
#' The ordinal tiers used to classify a program's competitive level when
#' measuring transfer *direction* (decision 0003). Higher is stronger, so a
#' move from a smaller level to a larger one is "up".
#'
#' @return A named integer vector mapping tier label to level.
#' @export
#'
#' @examples
#' \dontrun{conference_tier_levels()}
conference_tier_levels <- function() {
  c("FCS and below" = 1L, "Group of 5" = 2L, "Power" = 3L)
}

#' Build the season x conference -> tier lookup
#'
#' Derives the season-aware competitive tier for every `(season, conference)`
#' pair observed in `player_stats` (decision 0003), so the lookup refreshes as a
#' pure function of the ingested stats (decision 0017). A conference not in the
#' Power or Group-of-5 sets defaults to tier 1 (FCS and below) rather than being
#' dropped; `contract_conference_tiers()` then enforces full coverage.
#'
#' Season-awareness handles realignment over 2010-2026 (the Pac-12 collapse to
#' tier 2 from 2024, Western Athletic dropping FBS football after 2012). Note:
#' "FBS Independents" is tier 2 here, but Notre Dame is Power-level — apply that
#' team-level override in the transfer-direction feature step, not here.
#'
#' @param player_stats Long player-season stats with `season` and `conference`.
#'
#' @return A tibble with columns `season`, `conference`, `tier`, `tier_label`.
#' @export
build_conference_tiers <- function(player_stats) {
  rlang::check_installed("dplyr")
  tier_levels <- conference_tier_levels()
  power <- c("ACC", "SEC", "Big Ten", "Big 12", "Pac-12", "Pac-10", "Big East")
  g5 <- c(
    "American Athletic",
    "Mountain West",
    "Mid-American",
    "Sun Belt",
    "Conference USA",
    "FBS Independents",
    "Western Athletic"
  )
  player_stats |>
    dplyr::distinct(season, conference) |>
    dplyr::mutate(
      tier = dplyr::case_when(
        conference %in% power ~ 3L,
        conference %in% g5 ~ 2L,
        .default = 1L
      ),
      # Pac-12 collapses to two teams in 2024-2025 -> no longer Power.
      tier = dplyr::if_else(
        conference == "Pac-12" & season >= 2024,
        2L,
        tier
      ),
      # Western Athletic dropped FBS football after 2012 -> FCS thereafter.
      tier = dplyr::if_else(
        conference == "Western Athletic" & season >= 2013,
        1L,
        tier
      ),
      tier_label = names(tier_levels)[match(tier, unname(tier_levels))]
    ) |>
    dplyr::arrange(season, dplyr::desc(tier), conference)
}

#' Data contract for the season x conference -> tier lookup
#'
#' Validates the conference-tier lookup and, crucially, its *coverage*: every
#' `(season, conference)` pair present in `player_stats` must resolve to a tier,
#' so transfer-direction features never silently drop a conference. Intended to
#' run in the pipeline and fail fast (decision 0003).
#'
#' @param tiers Lookup table with columns `season`, `conference`, `tier`,
#'   `tier_label` (e.g. `data/conference_tiers.parquet`).
#' @param player_stats Player-season table with `season` and `conference`; the
#'   coverage universe the lookup must fully cover.
#' @param stop_on_fail If `TRUE` (default), raise an error when any check fails.
#'
#' @return Invisibly, a list of the two interrogated `pointblank` agents
#'   (`lookup`, `coverage`).
#' @export
contract_conference_tiers <- function(
  tiers,
  player_stats,
  stop_on_fail = TRUE
) {
  rlang::check_installed(
    "pointblank",
    reason = "to run the conference-tier data contract."
  )
  tier_levels <- conference_tier_levels()
  tiers <- dplyr::collect(tiers)
  player_stats <- dplyr::collect(player_stats)

  # Intrinsic checks on the lookup table itself.
  agent_lookup <-
    pointblank::create_agent(tiers, label = "conference_tiers: lookup") |>
    pointblank::col_exists(
      c("season", "conference", "tier", "tier_label")
    ) |>
    pointblank::col_vals_not_null(
      pointblank::vars(season, conference, tier, tier_label)
    ) |>
    pointblank::col_vals_in_set("tier", unname(tier_levels)) |>
    pointblank::col_vals_in_set("tier_label", names(tier_levels)) |>
    pointblank::col_vals_between("season", 2010, 2026) |>
    pointblank::rows_distinct(pointblank::vars(season, conference)) |>
    pointblank::interrogate()

  # Referential coverage: no (season, conference) in player_stats is unmapped.
  coverage <- player_stats |>
    dplyr::distinct(season, conference) |>
    dplyr::left_join(
      dplyr::select(tiers, season, conference, tier),
      by = c("season", "conference")
    ) |>
    dplyr::mutate(has_tier = !is.na(tier))

  agent_coverage <-
    pointblank::create_agent(coverage, label = "conference_tiers: coverage") |>
    pointblank::col_vals_equal("has_tier", TRUE) |>
    pointblank::interrogate()

  if (stop_on_fail) {
    if (!pointblank::all_passed(agent_lookup)) {
      cli::cli_abort(
        "The {.file conference_tiers} lookup failed its data contract."
      )
    }
    if (!pointblank::all_passed(agent_coverage)) {
      missing <- dplyr::filter(coverage, !has_tier)
      examples <- utils::head(paste(missing$season, missing$conference), 3)
      cli::cli_abort(c(
        "The {.file conference_tiers} lookup does not cover all of {.var player_stats}.",
        "x" = "{nrow(missing)} (season, conference) pair{?s} unmapped.",
        "i" = "e.g. {.val {examples}}"
      ))
    }
  }

  invisible(list(lookup = agent_lookup, coverage = agent_coverage))
}
