# Combine tab asset (plans/explorer.md step 5): every combine invitee's
# measurables and draft outcome, with the position group the Players tab
# knows them by. The position crosswalk is shared with the combine post (#64).

#' Map combine position codes to reader-facing position groups
#'
#' The combine (nflverse, Pro Football Reference codes) labels positions its
#' own way (`OT`, `OG`, `EDGE`, `OLB`, `SAF`, ...). This maps them onto the
#' same groups as [position_group()], so combine and CFBD views group
#' positions identically. Unknown codes become "Position not recorded".
#'
#' @param pos Character vector of combine `pos` codes.
#' @return Character vector of group labels (see [position_group_levels()]).
#' @export
combine_position_group <- function(pos) {
  map <- c(
    QB = "Quarterback",
    RB = "Running back",
    FB = "Running back",
    WR = "Receiver",
    TE = "Tight end",
    OT = "Offensive line",
    OG = "Offensive line",
    G = "Offensive line",
    C = "Offensive line",
    OL = "Offensive line",
    DE = "Defensive line",
    DT = "Defensive line",
    DL = "Defensive line",
    EDGE = "Defensive line",
    LB = "Linebacker",
    ILB = "Linebacker",
    OLB = "Linebacker",
    CB = "Defensive back",
    S = "Defensive back",
    SAF = "Defensive back",
    DB = "Defensive back",
    "CB/WR" = "Defensive back",
    K = "Special teams",
    P = "Special teams",
    LS = "Special teams"
  )
  out <- unname(map[pos])
  out[is.na(out)] <- "Position not recorded"
  out
}

#' Explorer combine position groups
#'
#' The Combine tab's position groups with their hash codes: the Players tab's
#' codes plus `OL`, since linemen have measurables even without box-score
#' stats.
#'
#' @return A tibble: `pos` (code), `group` (label), in display order.
#' @export
explorer_combine_groups <- function() {
  players <- dplyr::distinct(explorer_positions(), .data$pos, .data$group)
  tibble::tibble(
    pos = c(players$pos, "OL"),
    group = c(players$group, "Offensive line")
  ) |>
    dplyr::distinct() |>
    dplyr::arrange(match(.data$group, position_group_levels()))
}

#' Explorer combine measurables
#'
#' The axes the 3D scatter can use, first three the defaults.
#'
#' @return A tibble: `key` (column), `label`, `unit`.
#' @export
explorer_combine_measures <- function() {
  tibble::tibble(
    key = c(
      "height",
      "weight",
      "forty",
      "vertical",
      "broad_jump",
      "bench",
      "shuttle",
      "cone"
    ),
    label = c(
      "Height",
      "Weight",
      "40-yard dash",
      "Vertical jump",
      "Broad jump",
      "Bench press",
      "Shuttle",
      "3-cone drill"
    ),
    unit = c("in", "lb", "s", "in", "in", "reps", "s", "s")
  )
}

#' Explorer combine outcome categories
#'
#' Draft outcome for a combine invitee in the draft right after the combine,
#' in legend order. "Draft pending" marks a combine class whose draft has no
#' slots in the source yet (the draft has not happened in the published data,
#' not an in-flight draft). "UDFA, made NFL roster" marks an invitee without a
#' draft slot who still shows up in nflverse's player table: an undrafted free
#' agent who made an NFL roster, spanned by `rookie_season`/`last_season`.
#'
#' @return A tibble: `outcome` (code), `label`.
#' @export
explorer_combine_outcome_levels <- function() {
  tibble::tibble(
    outcome = c("r1", "r2_3", "r4_7", "udfa", "undrafted", "pending"),
    label = c(
      "Drafted, round 1",
      "Drafted, rounds 2-3",
      "Drafted, rounds 4-7",
      "UDFA, made NFL roster",
      "Not drafted",
      "Draft pending (draft not yet in data)"
    )
  )
}

#' Explorer combine table
#'
#' One row per combine invitee: measurables, the draft outcome that year,
#' and the CFBD link. `players_pos` is the Players-tab group of the
#' player's last stat season, so tapping a linked point opens the player in
#' the right group (`NA` when the player has no stat line there, e.g. most
#' linemen).
#'
#' The outcome label names the position a drafted player was picked at
#' (from CFBD `picks`, matched on draft year and overall pick), which can
#' differ from the position they worked out at (`combine_pos`).
#'
#' @param combine Cleaned, linked combine table.
#' @param player_seasons Output of [build_explorer_player_seasons()].
#' @param picks Optional CFBD draft picks (`year`, `overall`, `position`);
#'   without them the label leaves out the drafted position.
#' @param nfl_players Optional nflverse player crosswalk (`pfr_id`,
#'   `rookie_season`, `last_season`; see [ingest_nfl_players()]). An invitee
#'   without a draft slot who appears in it is relabelled an undrafted free
#'   agent who made an NFL roster; without the crosswalk they stay "Not
#'   drafted".
#' @return A tibble, one row per input row. `players_jersey` is the last
#'   stat season's college jersey number (display only).
#' @export
build_explorer_combine <- function(
  combine,
  player_seasons,
  picks = NULL,
  nfl_players = NULL
) {
  last_drafted <- suppressWarnings(max(
    combine$season[!is.na(combine$draft_round)]
  ))
  groups <- explorer_combine_groups()
  players_pos <- player_seasons |>
    dplyr::arrange(.data$player_id, dplyr::desc(.data$season)) |>
    dplyr::distinct(.data$player_id, .keep_all = TRUE) |>
    dplyr::select(
      athlete_id = "player_id",
      players_pos = "pos",
      players_jersey = "jersey"
    ) |>
    # The last stat season can lack a jersey while another season has one.
    dplyr::left_join(
      player_seasons |>
        dplyr::filter(!is.na(.data$jersey)) |>
        dplyr::summarise(
          jersey_any = dplyr::first(.data$jersey),
          .by = "player_id"
        ),
      by = c("athlete_id" = "player_id"),
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      players_jersey = dplyr::coalesce(.data$players_jersey, .data$jersey_any)
    ) |>
    dplyr::select(-"jersey_any")
  drafted_as <- if (is.null(picks)) {
    tibble::tibble(
      season = integer(),
      draft_ovr = integer(),
      drafted_pos = character()
    )
  } else {
    picks |>
      dplyr::transmute(
        season = as.integer(.data$year),
        draft_ovr = as.integer(.data$overall),
        drafted_pos = draft_position_code(.data$position)
      ) |>
      dplyr::distinct(.data$season, .data$draft_ovr, .keep_all = TRUE)
  }
  if (!"pfr_id" %in% names(combine)) {
    combine <- dplyr::mutate(combine, pfr_id = NA_character_)
  }
  combine |>
    dplyr::left_join(
      drafted_as,
      by = c("season", "draft_ovr"),
      relationship = "many-to-one"
    ) |>
    # UDFA relabel: the crosswalk sees undrafted invitees the draft-slot link
    # cannot (no NFL draft pick to match on).
    dplyr::left_join(
      if (is.null(nfl_players) || !"pfr_id" %in% names(combine)) {
        tibble::tibble(
          pfr_id = NA_character_,
          nfl_rookie = NA_integer_,
          nfl_last = NA_integer_
        )
      } else {
        nfl_players |>
          dplyr::select(
            "pfr_id",
            nfl_rookie = "rookie_season",
            nfl_last = "last_season"
          )
      },
      by = "pfr_id",
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      group = combine_position_group(.data$pos),
      outcome = dplyr::case_when(
        !is.na(.data$draft_round) ~ explorer_round_outcome(.data$draft_round),
        .data$season > last_drafted ~ "pending",
        !is.na(.data$nfl_rookie) ~ "udfa",
        TRUE ~ "undrafted"
      ),
      outcome_label = dplyr::case_when(
        !is.na(.data$draft_round) & !is.na(.data$drafted_pos) ~ sprintf(
          "Drafted as %s, R%d #%d (%s)",
          .data$drafted_pos,
          .data$draft_round,
          .data$draft_ovr,
          .data$draft_team
        ),
        !is.na(.data$draft_round) ~ sprintf(
          "Drafted R%d #%d (%s)",
          .data$draft_round,
          .data$draft_ovr,
          .data$draft_team
        ),
        .data$outcome == "udfa" ~ dplyr::if_else(
          .data$nfl_rookie == .data$nfl_last,
          sprintf("UDFA, NFL roster (%d)", .data$nfl_rookie),
          sprintf(
            "UDFA, NFL roster (%d-%d)",
            .data$nfl_rookie,
            .data$nfl_last
          )
        ),
        .data$outcome == "pending" ~
          "Draft pending (draft not yet in the data)",
        TRUE ~ "Not drafted"
      )
    ) |>
    dplyr::left_join(
      dplyr::rename(groups, group_pos = "pos"),
      by = "group",
      relationship = "many-to-one"
    ) |>
    dplyr::left_join(
      players_pos,
      by = "athlete_id",
      relationship = "many-to-one"
    ) |>
    dplyr::transmute(
      season = .data$season,
      name = .data$player_name,
      school = .data$school,
      combine_pos = .data$pos,
      pos = .data$group_pos,
      height = .data$height,
      weight = .data$weight,
      forty = .data$forty,
      vertical = .data$vertical,
      broad_jump = .data$broad_jump,
      bench = .data$bench,
      shuttle = .data$shuttle,
      cone = .data$cone,
      outcome = .data$outcome,
      outcome_label = .data$outcome_label,
      athlete_id = .data$athlete_id,
      players_pos = .data$players_pos,
      players_jersey = .data$players_jersey
    ) |>
    dplyr::arrange(.data$season, .data$name)
}

#' Write the Combine tab asset
#'
#' `combine.json` as an object of columns (one array per field), which is
#' about a third smaller gzipped than one object per row.
#'
#' @param explorer_combine Output of [build_explorer_combine()].
#' @param dir Output directory.
#' @return The written path.
#' @export
write_explorer_combine <- function(
  explorer_combine,
  dir = "vignettes/explorer-data"
) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, "combine.json")
  json <- jsonlite::toJSON(
    explorer_combine,
    dataframe = "columns",
    na = "null",
    digits = NA
  )
  writeLines(enc2utf8(json), path, useBytes = TRUE)
  path
}
