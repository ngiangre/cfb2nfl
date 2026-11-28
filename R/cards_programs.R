# Shared computations for the programs and conferences cards (feature F25,
# batch "programs"): the draft and undrafted rates by group, conference
# realignment, stat-line coverage by division, and the expected draftees from
# a fitted win curve. Each was computed inline in the three posts they
# migrate from; one tested copy here serves every card.

#' Eligible, drafted and undrafted counts and their rates
#'
#' Summarises credited draft rows (`team_draft`, one row per school, season
#' and position group) by whatever groups the input is grouped by.
#'
#' @param d Credited rows with `team`, `n_eligible`, `n_drafted` and
#'   `n_udfa`, optionally grouped.
#' @return One row per group: `schools`, `eligible`, `drafted`, `udfa`,
#'   `draft_rate` and `udfa_rate` (shares of eligible players).
#' @export
draft_rates <- function(d) {
  d |>
    dplyr::summarise(
      schools = dplyr::n_distinct(.data$team),
      eligible = sum(.data$n_eligible),
      drafted = sum(.data$n_drafted),
      udfa = sum(.data$n_udfa),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      draft_rate = .data$drafted / .data$eligible,
      udfa_rate = .data$udfa / .data$eligible
    )
}

#' Conference changes by FBS school and season
#'
#' A conference change is an FBS school playing in a different conference, or
#' as an independent, than in its previous FBS season. The Pac-10 became the
#' Pac-12 in 2011, a rename rather than a move.
#'
#' @param fbs FBS team-seasons with `team`, `season` and `conference`.
#' @return One row per change: `team`, `season`, `from` (the previous league)
#'   and `league` (the new one).
#' @export
realignment_moves <- function(fbs) {
  fbs |>
    dplyr::mutate(
      league = dplyr::if_else(
        .data$conference == "Pac-10",
        "Pac-12",
        .data$conference
      )
    ) |>
    dplyr::arrange(.data$team, .data$season) |>
    dplyr::group_by(.data$team) |>
    dplyr::mutate(from = dplyr::lag(.data$league)) |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(.data$from), .data$from != .data$league) |>
    dplyr::select("team", "season", "from", "league")
}

#' Share of played teams with at least one player stat line, by division
#'
#' @param played Team-seasons that played at least one recorded game, with
#'   `classification`, `has_stat_lines`, `n_stat_players` and `n_roster`.
#' @return One row per season and division (`FBS`, `FCS`, `Division II and
#'   below`): teams played, teams with a stat line (`with_stats`), teams with
#'   a roster (`with_roster`), `share` and `roster_share` of the played teams,
#'   and the median players with a stat line (`depth`) and roster size
#'   (`roster_size`) among teams with a stat line or a roster.
#' @export
stat_coverage <- function(played) {
  division_order <- c("FBS", "FCS", "Division II and below")
  played |>
    dplyr::mutate(
      division = dplyr::case_when(
        .data$classification == "fbs" ~ "FBS",
        .data$classification == "fcs" ~ "FCS",
        TRUE ~ "Division II and below"
      ),
      division = factor(.data$division, levels = division_order)
    ) |>
    dplyr::group_by(.data$season, .data$division) |>
    dplyr::summarise(
      played = dplyr::n(),
      with_stats = sum(.data$has_stat_lines),
      with_roster = sum(.data$n_roster > 0),
      depth = stats::median(.data$n_stat_players[.data$has_stat_lines]),
      roster_size = stats::median(.data$n_roster[.data$n_roster > 0]),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      share = .data$with_stats / .data$played,
      roster_share = .data$with_roster / .data$played
    )
}

#' Fit a win-curve per tier
#'
#' One binomial logistic regression per tier, of drafted against eligible
#' players (`cbind(drafted, eligible - drafted)`) on one predictor.
#'
#' @param d Schools with `tier` (a factor or character), `drafted`,
#'   `eligible` and the predictor.
#' @param x The predictor's column name, e.g. `"win_pct"` or `"sp"`.
#' @return A named list of `glm` fits, one per tier.
#' @export
fit_tier_curves <- function(d, x) {
  f <- stats::as.formula(paste("cbind(drafted, eligible - drafted) ~", x))
  lapply(split(d, as.character(d$tier)), \(g) {
    stats::glm(f, family = stats::binomial, data = g)
  })
}

#' Expected and drafted-above-expected draftees per school
#'
#' Multiplies each school's eligible players by the rate its tier's curve
#' ([fit_tier_curves()]) predicts for its predictor.
#'
#' @param d Schools with `tier`, `drafted`, `eligible` and the predictor.
#' @param x The predictor's column name.
#' @return `d` with `expected_rate`, `expected` and `above` (drafted minus
#'   expected) added.
#' @export
expected_draftees <- function(d, x) {
  fits <- fit_tier_curves(d, x)
  tier <- as.character(d$tier)
  rate <- rep(NA_real_, nrow(d))
  for (t in names(fits)) {
    i <- tier == t
    rate[i] <- stats::predict(fits[[t]], newdata = d[i, ], type = "response")
  }
  d$expected_rate <- rate
  d$expected <- rate * d$eligible
  d$above <- d$drafted - d$expected
  d
}

#' Colours for the three school tiers
#'
#' One palette for every card that plots by tier, so Power, Group of 5 and
#' FCS-and-below read the same wherever they appear.
#'
#' @return A named character vector of hex colours, one per tier label.
#' @export
tier_palette <- function() {
  # Neutral greys only: the hues of the drafted, undrafted and quarterback
  # colours and of the team colours that read as highlights stay off tiers.
  c(
    "Power" = "#374151",
    "Group of 5" = "#9ca3af",
    "FCS and below" = "#d1d5db"
  )
}

#' Team colours for highlights, with green and purple teams set to dark grey
#'
#' Green and purple are reserved for the drafted and undrafted colours and for
#' quarterbacks, so a team whose brand colour falls in those hues is shown in
#' dark grey instead. Greys (low saturation) keep their colour.
#'
#' @param cols Named character vector of hex colours, as [team_color_values()]
#'   returns.
#' @return The same vector with the green and purple entries replaced.
#' @export
highlight_colors <- function(cols) {
  ok <- !is.na(cols) & grepl("^#[0-9a-fA-F]{6}$", cols)
  if (!any(ok)) {
    return(cols)
  }
  hsv <- grDevices::rgb2hsv(grDevices::col2rgb(cols[ok]))
  hue <- hsv["h", ] * 360
  sat <- hsv["s", ]
  reserved <- sat >= 0.15 &
    ((hue >= 75 & hue <= 170) | (hue >= 240 & hue <= 330))
  idx <- which(ok)[reserved]
  cols[idx] <- "#374151"
  cols
}

#' One row per FBS school: record, draft rate and expected draftees
#'
#' The school table behind the winning-and-draftees cards. A school's tier is
#' the one it held in most of its FBS seasons; its record covers all of those
#' seasons, and its draft counts come from `credited` (final seasons).
#'
#' @param fbs_seasons FBS team-seasons with `team`, `season`, `tier_label`,
#'   `games_played`, `wins`, `losses` and `sp_overall`.
#' @param credited Credited draft rows with `team`, `n_eligible`, `n_drafted`.
#' @param tier_levels The tiers to keep, in order; schools in other tiers drop out.
#' @return One row per school: `eligible`, `drafted`, `draft_rate`, `wins`,
#'   `losses`, `games`, `win_pct`, `record_label`, `sp` (average SP+), `tier`,
#'   and the expected draftees from a per-tier win curve ([expected_draftees()]).
#' @export
school_record <- function(
  fbs_seasons,
  credited,
  tier_levels = c("Power", "Group of 5")
) {
  record <- fbs_seasons |>
    dplyr::group_by(.data$team) |>
    dplyr::summarise(
      games = sum(.data$games_played),
      wins = sum(.data$wins),
      losses = sum(.data$losses),
      sp = mean(.data$sp_overall, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      win_pct = .data$wins / .data$games,
      record_label = paste0(.data$wins, "-", .data$losses)
    )
  school_tier <- fbs_seasons |>
    dplyr::count(.data$team, .data$tier_label) |>
    dplyr::group_by(.data$team) |>
    dplyr::slice_max(.data$n, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select("team", tier = "tier_label")
  d <- credited |>
    dplyr::group_by(.data$team) |>
    dplyr::summarise(
      eligible = sum(.data$n_eligible),
      drafted = sum(.data$n_drafted),
      .groups = "drop"
    ) |>
    dplyr::mutate(draft_rate = .data$drafted / .data$eligible) |>
    dplyr::inner_join(record, by = "team") |>
    dplyr::inner_join(school_tier, by = "team") |>
    dplyr::filter(.data$tier %in% tier_levels) |>
    dplyr::mutate(tier = factor(.data$tier, levels = tier_levels))
  expected_draftees(d, "win_pct")
}

#' Draft, undrafted and NFL entry rates by school and position group
#'
#' One row per school and recorded position group, with the gaps the
#' school-by-position beeswarms plot.
#'
#' @param credited Credited draft rows (`team_draft`) with `team`,
#'   `position_group`, `n_eligible`, `n_drafted` and `n_udfa`.
#' @return The [draft_rates()] columns per `team` and `position_group` (a
#'   factor in [position_group_levels()] order), for groups with any eligible
#'   player, plus `entered` (drafted or signed undrafted), `entry_rate`,
#'   `udfa_gap` (undrafted rate minus draft rate) and `entry_gap` (rate not
#'   entering the NFL minus rate entering), the gaps in percentage points.
#' @export
school_position_rates <- function(credited) {
  credited |>
    dplyr::filter(.data$position_group %in% position_group_levels()) |>
    dplyr::group_by(.data$team, .data$position_group) |>
    draft_rates() |>
    dplyr::filter(.data$eligible > 0) |>
    dplyr::mutate(
      position_group = factor(
        .data$position_group,
        levels = position_group_levels()
      ),
      entered = .data$drafted + .data$udfa,
      entry_rate = .data$entered / .data$eligible,
      udfa_gap = 100 * (.data$udfa_rate - .data$draft_rate),
      entry_gap = 100 * (1 - 2 * .data$entry_rate)
    )
}

#' Each school's division and conference in its latest season
#'
#' @param team_season Team-seasons with `team`, `season`, `classification`
#'   (`fbs`, `fcs`, `ii`, `iii`) and `conference`.
#' @param last_season The latest season to look at.
#' @return One row per school with a recorded division: `division` (a factor:
#'   FBS, FCS, Division II, Division III) and `conference_group`, its FBS
#'   conference or "Not in FBS" (FBS independents share one group).
#' @export
school_division <- function(team_season, last_season) {
  labels <- c(
    fbs = "FBS",
    fcs = "FCS",
    ii = "Division II",
    iii = "Division III"
  )
  team_season |>
    dplyr::filter(
      .data$season <= last_season,
      .data$classification %in% names(labels)
    ) |>
    dplyr::group_by(.data$team) |>
    dplyr::slice_max(.data$season, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::transmute(
      .data$team,
      division = factor(unname(labels[.data$classification]), levels = labels),
      conference_group = dplyr::case_when(
        .data$classification != "fbs" ~ "Not in FBS",
        .data$conference == "FBS Independents" ~ "FBS independents",
        .default = .data$conference
      )
    )
}

#' One colour per FBS conference
#'
#' For figures coloured by a school's conference. No conference takes drafted
#' green, undrafted purple or quarterback orange, and none is a grey (dark
#' grey is the cards' highlight); schools outside FBS share the pale grey.
#'
#' @return A named character vector, conference group to hex colour, Power
#'   conferences first, as [school_division()] names them.
#' @export
conference_palette <- function() {
  c(
    "SEC" = "#C8102E",
    "Big Ten" = "#0B3C6E",
    "ACC" = "#5DA5DA",
    "Big 12" = "#E6B800",
    "Pac-12" = "#17BECF",
    "American Athletic" = "#8C564B",
    "Mountain West" = "#2F6F73",
    "Sun Belt" = "#C9A27E",
    "Mid-American" = "#8C8C00",
    "Conference USA" = "#F4A6A6",
    "FBS independents" = "#D6336C",
    "Not in FBS" = "#D1D5DB"
  )
}

#' One point shape per division
#'
#' @return A named integer vector of filled point shapes, FBS to Division III.
#' @export
division_shapes <- function() {
  c("FBS" = 16L, "FCS" = 17L, "Division II" = 15L, "Division III" = 18L)
}

#' A horizontal beeswarm of a gap per school, one row per position group
#'
#' @param d School position rows ([school_position_rates()]) with `team`,
#'   `position_group` and the columns named below.
#' @param gap,colour,tooltip Columns (unquoted) for the x position, the colour
#'   and the hover text.
#' @param values Named colours for `colour`; the legend follows their order.
#' @param shape Optional column (unquoted) for the point shape, with `shapes`
#'   its named shapes.
#' @param shapes Named point shapes for `shape`.
#' @param title,subtitle,x_label,caption Figure text.
#' @return A ggplot; hovering a dot highlights its school in every row.
#' @export
gap_beeswarm <- function(
  d,
  gap,
  colour,
  values,
  tooltip,
  title,
  subtitle,
  x_label,
  caption,
  shape = NULL,
  shapes = NULL
) {
  rlang::check_installed(c("ggplot2", "ggiraph", "ggbeeswarm"))
  d <- dplyr::mutate(d, position_group = forcats::fct_rev(.data$position_group))
  p <- ggplot2::ggplot(d, ggplot2::aes({{ gap }}, .data$position_group)) +
    ggplot2::geom_vline(
      xintercept = 0,
      linetype = "dashed",
      colour = "#6b7280"
    ) +
    ggiraph::geom_point_interactive(
      ggplot2::aes(
        colour = {{ colour }},
        shape = {{ shape }},
        tooltip = {{ tooltip }},
        data_id = .data$team
      ),
      position = ggbeeswarm::position_quasirandom(
        orientation = "y",
        width = 0.4
      ),
      size = 2.2,
      alpha = 0.85
    ) +
    ggplot2::scale_colour_manual(
      values = values,
      breaks = intersect(
        names(values),
        unique(as.character(dplyr::pull(d, {{ colour }})))
      ),
      name = NULL
    ) +
    ggplot2::labs(
      title = title,
      subtitle = subtitle,
      x = x_label,
      y = NULL,
      caption = caption
    ) +
    theme_cfb2nfl() +
    ggplot2::theme(
      plot.subtitle = ggplot2::element_text(size = ggplot2::rel(0.8))
    )
  if (!is.null(shapes)) {
    p <- p + ggplot2::scale_shape_manual(values = shapes, name = NULL)
  }
  p
}
