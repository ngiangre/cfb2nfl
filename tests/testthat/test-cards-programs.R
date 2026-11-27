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
