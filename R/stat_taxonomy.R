# Stat-phase taxonomy: turn the long player_stats (category / statType / stat)
# into something interpretable — which phase of the game a stat belongs to
# (offense / defense / special teams) and a plain-language label. Keyed at
# (category, statType) grain because a category alone can be phase-ambiguous:
# `fumbles/FUM` and `fumbles/LOST` are offense but `fumbles/REC` is defense.
# The canonical mapping is hand-authored data in inst/extdata/stat_taxonomy.csv.

#' Stat-phase taxonomy
#'
#' Reads the canonical `(category, statType) -> phase / label` mapping shipped
#' with the package (`inst/extdata/stat_taxonomy.csv`). This is the single
#' source of truth for making the long `player_stats` interpretable: it assigns
#' each stat a game **phase** (`offense` / `defense` / `special_teams`), a
#' plain-language `label` (so a bare `"TD"` becomes e.g. "Defensive touchdowns"
#' vs "Passing touchdowns"), and a `kind` (`scoring` / `volume` / `rate`).
#'
#' Coverage of every `(category, statType)` pair present in `player_stats` is
#' enforced by [contract_stat_taxonomy()], so a new stat appearing in a refresh
#' fails fast rather than going silently unlabeled.
#'
#' @return A tibble with columns `category`, `statType`, `phase`, `label`,
#'   `kind`, `description`.
#' @export
#'
#' @examples
#' head(stat_taxonomy())
stat_taxonomy <- function() {
  rlang::check_installed("tibble")
  path <- app_sys("extdata", "stat_taxonomy.csv")
  if (!nzchar(path)) {
    cli::cli_abort(
      "{.file stat_taxonomy.csv} not found; is the package installed?"
    )
  }
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE) |>
    tibble::as_tibble()
}

#' Attach phase and plain-language labels to long player stats
#'
#' Left-joins [stat_taxonomy()] onto a long `player_stats` slice on
#' `(category, statType)`, attaching `phase`, `label`, and `kind`. The reusable
#' "make the stats interpretable" helper used by [player_dossier()] and any
#' phase-aware figure. Unmatched pairs get `NA` phase/label — the pipeline's
#' [contract_stat_taxonomy()] guards against that at the population level.
#'
#' @param stats A long `player_stats`-shaped table with `category` and
#'   `statType` columns.
#' @param taxonomy The taxonomy lookup; defaults to [stat_taxonomy()].
#'
#' @return `stats` with `phase`, `label`, and `kind` attached. Same row count.
#' @export
label_stats <- function(stats, taxonomy = stat_taxonomy()) {
  stats |>
    dplyr::left_join(
      dplyr::select(
        taxonomy,
        "category",
        "statType",
        "phase",
        "label",
        "kind"
      ),
      by = c("category", "statType")
    )
}
