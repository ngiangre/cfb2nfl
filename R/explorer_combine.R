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
#' slots in the source yet.
#'
#' @return A tibble: `outcome` (code), `label`.
#' @export
explorer_combine_outcome_levels <- function() {
  tibble::tibble(
    outcome = c("r1", "r2_3", "r4_7", "undrafted", "pending"),
    label = c(
      "Drafted, round 1",
      "Drafted, rounds 2-3",
      "Drafted, rounds 4-7",
      "Not drafted",
      "Draft pending"
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
#' @param combine Cleaned, linked combine table.
#' @param player_seasons Output of [build_explorer_player_seasons()].
#' @return A tibble, one row per input row.
#' @export
build_explorer_combine <- function(combine, player_seasons) {
  last_drafted <- suppressWarnings(max(
    combine$season[!is.na(combine$draft_round)]
  ))
  groups <- explorer_combine_groups()
  players_pos <- player_seasons |>
    dplyr::arrange(.data$player_id, dplyr::desc(.data$season)) |>
    dplyr::distinct(.data$player_id, .keep_all = TRUE) |>
    dplyr::select(athlete_id = "player_id", players_pos = "pos")
  combine |>
    dplyr::mutate(
      group = combine_position_group(.data$pos),
      outcome = dplyr::case_when(
        !is.na(.data$draft_round) ~ explorer_round_outcome(.data$draft_round),
        .data$season > last_drafted ~ "pending",
        TRUE ~ "undrafted"
      ),
      outcome_label = dplyr::case_when(
        !is.na(.data$draft_round) ~ sprintf(
          "Drafted R%d #%d (%s)",
          .data$draft_round,
          .data$draft_ovr,
          .data$draft_team
        ),
        .data$outcome == "pending" ~ "Draft pending",
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
      players_pos = .data$players_pos
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
