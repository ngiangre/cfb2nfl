# Visualization helpers (decision 0006). R htmlwidgets are the default stack;
# these helpers keep charts themed consistently and traceable to a single
# pipeline target. Observable JS is reserved for bespoke explorables on the site.

#' Shared ggplot2 theme (large, accessible fonts)
#'
#' The canonical project theme. Built on `theme_minimal()` with a large base
#' size and bold, legible titles so figures read well on the site and in talks
#' (figure-styling standard, decision 0006). Use everywhere rather than
#' re-theming per plot.
#'
#' @param base_size Base font size in points (default 16 for accessibility).
#' @param base_family Base font family (default "").
#' @return A ggplot2 theme object.
#' @export
theme_cfb2nfl <- function(base_size = 16, base_family = "") {
  rlang::check_installed("ggplot2")
  ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      # All text bold (figure-styling standard, decision 0006).
      text = ggplot2::element_text(face = "bold"),
      plot.title.position = "plot",
      plot.title = ggplot2::element_text(
        face = "bold",
        size = ggplot2::rel(1.25)
      ),
      plot.subtitle = ggplot2::element_text(
        size = ggplot2::rel(1.0),
        colour = "grey30"
      ),
      axis.title = ggplot2::element_text(size = ggplot2::rel(0.95)),
      axis.text = ggplot2::element_text(size = ggplot2::rel(0.9)),
      legend.position = "top",
      legend.text = ggplot2::element_text(size = ggplot2::rel(0.9)),
      strip.text = ggplot2::element_text(
        face = "bold",
        size = ggplot2::rel(0.95)
      ),
      panel.grid.minor = ggplot2::element_blank()
    )
}

#' Shared ggplot2 theme (retained alias)
#'
#' Backward-compatible alias that delegates to [theme_cfb2nfl()] so existing
#' figures pick up the accessible-font standard. Prefer [theme_cfb2nfl()] in
#' new code.
#'
#' @return A ggplot2 theme object.
#' @export
viz_theme <- function() {
  theme_cfb2nfl()
}

#' Team brand-color values for a discrete color/fill scale
#'
#' Builds a named vector (team -> hex) from the cleaned team dimension
#' ([clean_teams()]), for use with the team scales below. Team colors are
#' **display only** and joined by school name (decision 0008); this covers
#' college programs only, so teams absent from `teams` (e.g. NFL clubs) fall
#' through to the scale's `na.value`.
#'
#' @param teams Cleaned team dimension with `team` and `color` columns.
#' @return A named character vector mapping team name to hex color.
#' @export
team_color_values <- function(teams) {
  teams |>
    dplyr::filter(
      !is.na(.data$color),
      .data$color != "#null",
      grepl("^#", .data$color)
    ) |>
    dplyr::distinct(.data$team, .data$color) |>
    tibble::deframe()
}

#' Team brand-color fill scale
#'
#' A `scale_fill_manual()` keyed on team name using each program's brand color.
#' Teams not present in `teams` (e.g. NFL clubs, which are outside the college
#' team dimension) render in `na.value`.
#'
#' @param teams Cleaned team dimension (see [team_color_values()]).
#' @param na.value Fill for teams without a brand color (default neutral grey).
#' @param ... Passed to [ggplot2::scale_fill_manual()].
#' @return A ggplot2 scale.
#' @export
scale_fill_team <- function(teams, na.value = "#6b7280", ...) {
  rlang::check_installed("ggplot2")
  ggplot2::scale_fill_manual(
    values = team_color_values(teams),
    na.value = na.value,
    ...
  )
}

#' Team brand-color colour scale
#'
#' Colour counterpart to [scale_fill_team()].
#'
#' @param teams Cleaned team dimension (see [team_color_values()]).
#' @param na.value Colour for teams without a brand color (default neutral grey).
#' @param ... Passed to [ggplot2::scale_colour_manual()].
#' @return A ggplot2 scale.
#' @export
scale_color_team <- function(teams, na.value = "#6b7280", ...) {
  rlang::check_installed("ggplot2")
  ggplot2::scale_colour_manual(
    values = team_color_values(teams),
    na.value = na.value,
    ...
  )
}
