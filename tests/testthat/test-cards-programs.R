# Shared computations for the programs and conferences cards (feature F25).

test_that("draft_rates sums credited rows and takes the rates of eligible players", {
  d <- tibble::tibble(
    team = c("A", "A", "B"),
    n_eligible = c(10L, 5L, 5L),
    n_drafted = c(2L, 1L, 0L),
    n_udfa = c(1L, 0L, 2L)
  )
  out <- draft_rates(d)
  expect_equal(out$schools, 2L)
  expect_equal(out$eligible, 20L)
  expect_equal(out$drafted, 3L)
  expect_equal(out$draft_rate, 0.15)
  expect_equal(out$udfa_rate, 0.15)

  by_team <- draft_rates(dplyr::group_by(d, .data$team))
  expect_equal(by_team$draft_rate, c(0.2, 0))
})

test_that("realignment_moves counts a conference change, not the Pac-10 rename", {
  fbs <- tibble::tibble(
    team = c("Boise State", "Boise State", "Boise State", "Oregon", "Oregon"),
    season = c(2010L, 2011L, 2012L, 2010L, 2011L),
    conference = c("WAC", "WAC", "Mountain West", "Pac-10", "Pac-10")
  )
  moves <- realignment_moves(fbs)
  expect_equal(nrow(moves), 1L)
  expect_equal(moves$team, "Boise State")
  expect_equal(moves$season, 2012L)
  expect_equal(moves$from, "WAC")
  expect_equal(moves$league, "Mountain West")
})

test_that("stat_coverage counts teams with a stat line by division and season", {
  played <- tibble::tibble(
    season = c(2020L, 2020L, 2020L, 2021L),
    team = c("A", "B", "C", "A"),
    classification = c("fbs", "fbs", "fcs", "fcs"),
    has_stat_lines = c(TRUE, FALSE, FALSE, TRUE),
    n_stat_players = c(30L, 0L, 0L, 20L),
    n_roster = c(80L, 70L, 0L, 60L)
  )
  cov <- stat_coverage(played)
  fbs_2020 <- cov[cov$season == 2020L & cov$division == "FBS", ]
  expect_equal(fbs_2020$played, 2L)
  expect_equal(fbs_2020$with_stats, 1L)
  expect_equal(fbs_2020$share, 0.5)
  fcs_2020 <- cov[cov$season == 2020L & cov$division == "FCS", ]
  expect_equal(fcs_2020$with_roster, 0L)
  expect_equal(levels(cov$division), c("FBS", "FCS", "Division II and below"))
})

win_fixture <- function() {
  set.seed(1)
  n <- 40L
  tibble::tibble(
    team = paste0("S", seq_len(n)),
    tier = factor(
      rep(c("Power", "Group of 5"), each = n / 2),
      levels = c("Power", "Group of 5")
    ),
    win_pct = stats::runif(n, 0.2, 0.9),
    eligible = sample(5:30, n, replace = TRUE)
  ) |>
    dplyr::mutate(
      drafted = stats::rbinom(n, eligible, 0.1 + 0.3 * win_pct)
    )
}

test_that("expected_draftees fits each tier and matches its total drafted", {
  d <- win_fixture()
  out <- expected_draftees(d, "win_pct")
  expect_equal(nrow(out), nrow(d))
  for (t in levels(d$tier)) {
    i <- out$tier == t
    # a logistic fit with an intercept reproduces its tier's total drafted
    expect_equal(sum(out$expected[i]), sum(out$drafted[i]), tolerance = 1e-6)
  }
  expect_true(all(out$expected_rate > 0 & out$expected_rate < 1))
  expect_equal(out$above, out$drafted - out$expected)
})

test_that("tier_palette names the three tiers and gives each a distinct colour", {
  pal <- tier_palette()
  expect_equal(names(pal), c("Power", "Group of 5", "FCS and below"))
  expect_equal(length(unique(pal)), 3L)
  expect_true(all(grepl("^#[0-9a-f]{6}$", pal)))
})

test_that("school_record builds one row per school with record, tier and expected draftees", {
  set.seed(2)
  schools <- paste0("S", 1:12)
  tiers <- rep(c("Power", "Group of 5"), each = 6)
  seasons <- tidyr::expand_grid(team = schools, season = 2010:2011) |>
    dplyr::mutate(
      tier_label = tiers[match(team, schools)],
      classification = "fbs",
      games_played = 12L,
      wins = sample(3:10, dplyr::n(), replace = TRUE),
      losses = 12L - wins,
      sp_overall = runif(dplyr::n(), -5, 20)
    )
  credited <- tibble::tibble(
    team = schools,
    n_eligible = sample(5:30, 12, replace = TRUE)
  )
  credited$n_drafted <- rbinom(12, credited$n_eligible, 0.2)
  out <- school_record(seasons, credited)
  expect_equal(nrow(out), 12L)
  expect_equal(levels(out$tier), c("Power", "Group of 5"))
  expect_equal(out$wins + out$losses, out$games)
  expect_true(all(out$record_label == paste0(out$wins, "-", out$losses)))
  for (t in levels(out$tier)) {
    i <- out$tier == t
    expect_equal(sum(out$expected[i]), sum(out$drafted[i]), tolerance = 1e-6)
  }
  # a school whose only seasons are in FCS is not in the table
  fcs <- seasons
  fcs$tier_label[fcs$team == "S1"] <- "FCS and below"
  expect_false("S1" %in% school_record(fcs, credited)$team)
})

test_that("highlight_colors sets green and purple teams to dark grey and keeps the rest", {
  cols <- c(
    Oregon = "#154733",
    Washington = "#4b2e83",
    Alabama = "#9e1b32",
    Grey = "#808080",
    Missing = NA
  )
  out <- highlight_colors(cols)
  expect_equal(unname(out[["Oregon"]]), "#374151")
  expect_equal(unname(out[["Washington"]]), "#374151")
  expect_equal(unname(out[["Alabama"]]), "#9e1b32")
  expect_equal(unname(out[["Grey"]]), "#808080")
  expect_true(is.na(out[["Missing"]]))
})

test_that("tier_palette avoids the reserved drafted, undrafted and quarterback hues", {
  pal <- tier_palette()
  expect_false(any(
    toupper(pal) %in% c("#F59E0B", "#1B9E77", "#7570B3", "#D95F02")
  ))
})

test_that("school_position_rates keeps recorded groups with eligible players and takes the gaps", {
  credited <- tibble::tibble(
    team = c("A", "A", "A", "B"),
    position_group = c(
      "Quarterback",
      "Quarterback",
      "Position not recorded",
      "Receiver"
    ),
    n_eligible = c(6L, 4L, 3L, 0L),
    n_drafted = c(1L, 1L, 1L, 0L),
    n_udfa = c(3L, 0L, 0L, 0L)
  )
  out <- school_position_rates(credited)
  expect_equal(nrow(out), 1L)
  expect_equal(as.character(out$position_group), "Quarterback")
  expect_equal(levels(out$position_group), position_group_levels())
  expect_equal(out$entered, 5L)
  expect_equal(out$udfa_gap, 100 * (0.3 - 0.2))
  expect_equal(out$entry_gap, 0)
})

test_that("school_division takes each school's latest division and FBS conference", {
  ts <- tibble::tibble(
    team = c("JMU", "JMU", "Ohio State", "Navy", "Ferris State", "Ghost"),
    season = c(2021L, 2023L, 2025L, 2025L, 2025L, 2025L),
    classification = c("fcs", "fbs", "fbs", "fbs", "ii", NA),
    conference = c(
      "CAA",
      "Sun Belt",
      "Big Ten",
      "FBS Independents",
      "GLIAC",
      NA
    )
  )
  out <- school_division(ts, last_season = 2025L)
  expect_equal(nrow(out), 4L)
  get <- \(t, col) as.character(out[[col]][out$team == t])
  expect_equal(get("JMU", "division"), "FBS")
  expect_equal(get("JMU", "conference_group"), "Sun Belt")
  expect_equal(get("Navy", "conference_group"), "FBS independents")
  expect_equal(get("Ferris State", "conference_group"), "Not in FBS")
  expect_equal(
    levels(out$division),
    c("FBS", "FCS", "Division II", "Division III")
  )
  expect_true(all(out$conference_group %in% names(conference_palette())))
})

test_that("conference_palette gives each group a distinct colour off the reserved hues", {
  pal <- conference_palette()
  expect_equal(anyDuplicated(unname(pal)), 0L)
  expect_equal(highlight_colors(pal), pal)
  expect_false(any(toupper(pal) %in% c("#1B9E77", "#7570B3", "#D95F02")))
  sat <- grDevices::rgb2hsv(grDevices::col2rgb(pal))["s", ]
  expect_true(all(sat[names(pal) != "Not in FBS"] >= 0.15))
})

test_that("gap_beeswarm builds one row per position group", {
  d <- school_position_rates(tibble::tibble(
    team = c("A", "B"),
    position_group = c("Quarterback", "Receiver"),
    n_eligible = c(10L, 10L),
    n_drafted = c(1L, 3L),
    n_udfa = c(2L, 1L)
  )) |>
    dplyr::mutate(side = c("x", "y"), division = c("FBS", "FCS"))
  p <- gap_beeswarm(
    d,
    udfa_gap,
    side,
    c(x = "#111827", y = "#9CA3AF"),
    team,
    "Title",
    "Subtitle",
    "Gap",
    "Caption",
    shape = division,
    shapes = division_shapes()
  )
  built <- ggplot2::ggplot_build(p)
  expect_equal(nrow(built$data[[2]]), 2L)
  expect_equal(levels(p$data$position_group)[1], "Special teams")
})
