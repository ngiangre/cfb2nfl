# Generates the rotating hero-card figures for the site front page (README.md).
# One PNG per player: the first five picks of the 2024 and 2025 NFL drafts.
# Run with the project root as wd; outputs to man/figures/hero/ (committed, so
# the README/site need no data access to display the hero).
#
# The plotting logic mirrors vignettes/2026-08-27-buechele-allen.qmd: the
# college -> NFL team-by-season tile plot, in each team's brand colors, with
# logos (display only, decision 0008).

library(arrow)
library(dplyr)
library(ggplot2)
library(ggpath)

# Site palette (see altdoc/custom.scss). The PNG background matches the hero
# card surface so the image blends into the card.
PAL <- list(
  bg = "#EEF1F5",
  ink = "#1A2332",
  slate = "#5B6678",
  teal = "#0FA3B1"
)

dir.create("man/figures/hero", showWarnings = FALSE, recursive = TRUE)

# Relative luminance (WCAG): pick the logo variant with better contrast per tile.
rel_lum <- function(hex) {
  ok <- grepl("^#[0-9A-Fa-f]{6}$", hex)
  out <- rep(NA_real_, length(hex))
  if (any(ok)) {
    m <- grDevices::col2rgb(hex[ok]) / 255
    lin <- ifelse(m <= 0.03928, m / 12.92, ((m + 0.055) / 1.055)^2.4)
    out[ok] <- 0.2126 * lin[1, ] + 0.7152 * lin[2, ] + 0.0722 * lin[3, ]
  }
  out
}

college_meta <- open_dataset("data/teams.parquet") |>
  select(team, color, logo_light, logo_dark) |>
  collect() |>
  transmute(
    team,
    name = team,
    color,
    logo = if_else(
      !is.na(rel_lum(color)) & rel_lum(color) < 0.5,
      logo_dark,
      logo_light
    )
  )
nfl_meta <- nflreadr::load_teams(current = FALSE) |>
  transmute(
    team = team_abbr,
    name = team_name,
    color = team_color,
    logo = team_logo_espn
  )
team_lookup <- bind_rows(college_meta, nfl_meta) |>
  distinct(team, .keep_all = TRUE)

# Subjects: first five picks of the 2024 and 2025 drafts. gsis_id comes from the
# nflverse draft table joined on draft slot (year/round/pick), the reliable key.
slots <- open_dataset("data/picks.parquet") |>
  filter(year %in% c(2024, 2025), round == 1, pick <= 5) |>
  select(year, round, pick, overall, name, collegeAthleteId, nflTeam) |>
  collect() |>
  left_join(
    open_dataset("data/nfl_draft_picks.parquet") |>
      filter(season %in% c(2024, 2025), round == 1, pick <= 5) |>
      select(season, round, pick, gsis_id, position) |>
      collect(),
    by = c("year" = "season", "round", "pick")
  ) |>
  transmute(
    who = name,
    cfb_athlete_id = as.character(collegeAthleteId),
    gsis_id,
    pos = position,
    draft_year = year,
    draft_pick = overall
  ) |>
  arrange(draft_year, draft_pick)
stopifnot(nrow(slots) == 10, !anyNA(slots$gsis_id))

spine <- player_trajectory(
  slots |> select(who, cfb_athlete_id, gsis_id),
  roster = open_dataset("data/roster.parquet"),
  nfl_rosters = open_dataset("data/nfl_rosters.parquet"),
  nfl_draft_picks = open_dataset("data/nfl_draft_picks.parquet")
)

meta <- spine |>
  left_join(team_lookup, by = "team") |>
  group_by(who) |>
  # Current (most recent) club and first college club: shown large above the
  # timeline, college -> NFL with an arrow between.
  slice_max(season, n = 1) |>
  ungroup() |>
  select(who, season, team, name, logo, color) |>
  rename(nfl_logo = logo, nfl_team = team, nfl_team_name = name) |>
  left_join(select(slots, who, draft_year, draft_pick, pos), by = "who") |>
  left_join(
    spine |>
      filter(stage == "College") |>
      group_by(who) |>
      slice_min(season, n = 1) |>
      ungroup() |>
      select(who, team) |>
      left_join(team_lookup, by = "team") |>
      select(who, cfb_logo = logo, cfb_team_name = name),
    by = "who"
  )
stopifnot(nrow(meta) == 10, !anyNA(meta$cfb_logo))

hero_plot <- function(player, spine, meta) {
  m <- meta[meta$who == player, ]
  s <- spine |>
    filter(who == player) |>
    left_join(team_lookup, by = "team") |>
    mutate(row = "Career")
  stopifnot(!anyNA(s$color), !anyNA(s$logo), nrow(s) > 0, nrow(m) == 1)

  ggplot() +
    # First college club -> current NFL club, large, above the timeline.
    geom_from_path(
      data = tibble::tibble(x = min(s$season), y = 2.7, path = m$cfb_logo),
      aes(x, y, path = path),
      height = 0.45
    ) +
    geom_segment(
      data = tibble::tibble(
        x = min(s$season) + 1.2,
        xend = max(s$season) - 1.2
      ),
      aes(x = x, xend = xend, y = 2.7, yend = 2.7),
      linewidth = 1.1,
      color = PAL$ink,
      arrow = grid::arrow(length = unit(12, "pt"), type = "closed")
    ) +
    geom_from_path(
      data = tibble::tibble(x = max(s$season), y = 2.7, path = m$nfl_logo),
      aes(x, y, path = path),
      height = 0.45
    ) +
    geom_tile(
      data = s,
      aes(x = season, y = 1, fill = color),
      color = "white",
      linewidth = 0.8,
      height = 0.7
    ) +
    geom_from_path(
      data = s,
      aes(x = season, y = 1, path = logo),
      height = 0.11
    ) +
    scale_fill_identity() +
    scale_x_continuous(
      breaks = sort(unique(s$season)),
      expand = c(0.03, 0.03)
    ) +
    scale_y_continuous(limits = c(0.4, 3.8), expand = c(0, 0)) +
    labs(
      title = paste0(toupper(player), ", ", m$pos),
      subtitle = paste0(
        "No. ",
        m$draft_pick,
        " overall, ",
        m$draft_year,
        " NFL Draft \u00b7 team by season, college through the NFL"
      ),
      x = NULL,
      y = NULL,
      caption = "Data: CFBD + nflverse \u00b7 cfb2nfl"
    ) +
    theme_cfb2nfl(base_size = 15) +
    theme(
      plot.background = element_rect(fill = PAL$bg, color = NA),
      panel.background = element_rect(fill = PAL$bg, color = NA),
      panel.grid = element_blank(),
      axis.text.y = element_blank(),
      plot.title = element_text(size = 30, face = "bold", color = PAL$ink),
      plot.subtitle = element_text(
        size = 14,
        face = "plain",
        color = PAL$slate
      ),
      plot.caption = element_text(size = 10, face = "plain", color = PAL$slate),
      axis.text.x = element_text(size = 13, face = "bold", color = PAL$ink),
      plot.margin = margin(14, 14, 10, 14)
    )
}

for (i in seq_len(nrow(slots))) {
  player <- slots$who[i]
  slug <- tolower(gsub("-+$", "", gsub("[^a-z]+", "-", tolower(player))))
  p <- hero_plot(player, spine, meta)
  out <- file.path("man/figures/hero", sprintf("hero_%02d_%s.png", i, slug))
  ggsave(out, p, width = 9.5, height = 5.4, dpi = 200, bg = PAL$bg)
  cat("wrote", out, "\n")
}

# Rotating hero image (the tinytable pattern): loop the frames into one GIF so
# it renders identically on GitHub and on the Quarto site.
frames <- sort(list.files(
  "man/figures/hero",
  pattern = "^hero_[0-9]+_.*[.]png$",
  full.names = TRUE
))
stopifnot(length(frames) == 10)
gif <- magick::image_read(frames) |>
  magick::image_scale("1200") |>
  magick::image_join()
# 5 s per frame (delay in centiseconds), endless loop.
gif <- magick::image_animate(gif, delay = 500, loop = 0)
magick::image_write(gif, "man/figures/hero/hero.gif")
cat("wrote man/figures/hero/hero.gif\n")
