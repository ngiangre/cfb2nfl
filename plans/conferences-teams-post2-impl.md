# Post 2 (who produces draftees, by conference, school, position) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish Post 2 of the series in `plans/conferences-teams.md`: draft and UDFA rates by tier, conference, school and position group, with small-sample schools shrunk toward their group so "above average" is fair.

**Architecture:** One new tested helper `shrink_rate()` in `R/rates.R` (beta-binomial empirical Bayes, method of moments, per group). The post reads `team_draft` / `team_season` / `picks` / `teams` from the DuckDB bundle. No new targets or tables.

**Tech Stack:** R, dplyr, testthat, Quarto, ggplot2 + ggiraph, knitr::kable.

**Spec:** `plans/conferences-teams.md` (Post 2 section; read the "Superseded as built" note), decision 0033, `inst/dict/team_draft.yml`. Style: AGENTS.md "Blog style" + "Vignette writing critiques".

---

## Facts measured 2026-10-31 (credit seasons 2013–2025 ≈ classes 2014–2026)

- Draft rate (drafted / eligible exits): Power 13.8% (2,561 / 18,611), Group of 5 2.7% (483 / 17,590), FCS and below 1.1% (85 / 8,047; rosters incomplete, show as one aggregate only).
- UDFA rate: Power 10.6%, G5 5.7%, FCS-and-below 5.0%; the tier gap is much narrower than for draft picks.
- Conference draft rates (credit-season conference): SEC 18.7%, Big Ten 13.9%, Pac-12 12.5%, ACC 11.9%, Big 12 9.7%, FBS Independents 6.0%, American 4.4%, Mountain West 3.1%, C-USA 2.2%, MAC 2.1%, Sun Belt 1.8%.
- Schools: 137 FBS; eligible exits per school 19–436. Alabama 40.7% (116 / 285), Ohio State 35.3%, LSU 32.2%, Georgia 29.1%, Michigan 26.8%.
- Position leaders by count: DB Alabama 22 / Ohio State 19 / Penn State 17; DL Ohio State 22, Alabama 19, Clemson 19; LB Alabama 20, Georgia 18, Michigan 15; OL Georgia 19, Ohio State 18, Alabama 17; QB Alabama/Ohio State 6; WR LSU 15, Ohio State 13; RB Alabama 12 of 16; TE Notre Dame 9.
- UDFA top 25 vs drafted top 25 by count: 16 overlap; UDFA-only include Tennessee, Nebraska, Pittsburgh, Illinois, Wisconsin, Arkansas, Baylor, Oklahoma State, Rutgers.
- Fan nicknames to check (descriptive, no verdict emojis): "DBU" (LSU), "Linebacker U" (Penn State), "WRU" (several claim it; LSU leads by count), "Tailback U" (USC), "QBU" (BYU / Miami / USC claims). Verify each school's rank in data before naming.

## Task A: `shrink_rate()`

**Files:** Create `R/rates.R`, `tests/testthat/test-rates.R`.

- [ ] **Step 1: Write the failing tests**

```r
test_that("shrink_rate leaves rates alone when units do not vary", {
  x <- c(10L, 20L, 30L)
  n <- c(100L, 200L, 300L)
  expect_equal(shrink_rate(x, n), rep(0.1, 3))
})

test_that("shrink_rate pulls small units toward the group rate more than large ones", {
  x <- c(1L, 40L, 5L, 60L, 10L)
  n <- c(1L, 100L, 100L, 300L, 200L)
  out <- shrink_rate(x, n)
  m <- sum(x) / sum(n)
  # The 1-for-1 unit moves most of the way back toward the pooled rate.
  expect_lt(abs(out[1] - m), abs(1 - m) / 2)
  # The 40/100 unit stays well above the pooled rate.
  expect_gt(out[2], m)
  expect_lt(abs(out[2] - 0.4), abs(out[1] - 1))
  expect_true(all(out > 0 & out < 1))
})

test_that("shrink_rate shrinks within each group", {
  x <- c(1L, 2L, 30L, 40L)
  n <- c(100L, 100L, 100L, 100L)
  g <- c("a", "a", "b", "b")
  out <- shrink_rate(x, n, group = g)
  expect_true(all(out[g == "a"] < 0.05))
  expect_true(all(out[g == "b"] > 0.25))
})

test_that("shrink_rate returns NA for units with no trials", {
  out <- shrink_rate(c(0L, 5L, 10L), c(0L, 50L, 60L))
  expect_true(is.na(out[1]))
  expect_false(anyNA(out[-1]))
})
```

- [ ] **Step 2:** `Rscript -e 'devtools::test(filter = "rates")'` → FAIL (function not found).

- [ ] **Step 3: Implement `R/rates.R`**

```r
# Rates for small groups (Post 2 of plans/conferences-teams.md): a school
# with 1 draftee from 3 players should not outrank Alabama, so raw rates are
# pulled toward their group's rate in proportion to how little data they have.

#' Shrink rates toward their group rate (beta-binomial empirical Bayes)
#'
#' Estimates, within each group, how much true rates vary between units
#' beyond binomial sampling noise (method of moments), then returns each
#' unit's posterior mean `(x + k * m) / (n + k)`, where `m` is the group's
#' pooled rate and `k` the prior strength. Units with few trials move most of
#' the way to `m`; units with many barely move. If the units vary no more
#' than chance alone predicts, every unit gets `m`.
#'
#' @param x Integer successes per unit (e.g. players drafted).
#' @param n Integer trials per unit (e.g. eligible players), `x <= n`.
#' @param group Optional grouping vector (e.g. conference); shrinkage is
#'   toward each group's own pooled rate. `NULL` pools everything.
#' @return Numeric vector of shrunk rates, `NA` where `n == 0`.
#' @export
shrink_rate <- function(x, n, group = NULL) {
  stopifnot(length(x) == length(n), all(x <= n, na.rm = TRUE))
  if (is.null(group)) group <- rep(1L, length(x))
  out <- rep(NA_real_, length(x))
  for (g in unique(group)) {
    i <- which(group == g & n > 0)
    if (length(i) == 0L) next
    m <- sum(x[i]) / sum(n[i])
    p <- x[i] / n[i]
    # Between-unit variance of raw rates minus the share expected from
    # binomial noise alone is the true-rate variance tau2.
    # Trial-weighted, so binomial noise contributes m(1-m) per unit / total n.
    s2 <- stats::weighted.mean((p - m)^2, n[i])
    noise <- m * (1 - m) * length(i) / sum(n[i])
    tau2 <- s2 - noise
    out[i] <- if (length(i) < 2L || tau2 <= 0 || m %in% c(0, 1)) {
      m
    } else {
      k <- max(m * (1 - m) / tau2 - 1, 0)
      (x[i] + k * m) / (n[i] + k)
    }
  }
  out
}
```

- [ ] **Step 4:** Run tests → PASS. If the "pulls small units" test fails because the moment estimate gives `tau2 <= 0` on that fixture, widen the fixture's spread (keep the assertions); do not weaken the assertions.
- [ ] **Step 5:** `devtools::document()`, `air format R/rates.R tests/testthat/test-rates.R`, full `devtools::test()`, commit `feat(rates): shrink_rate empirical-Bayes helper` (specific paths, Co-Authored-By trailer).

## Task B: Post 2

**Files:** Create `vignettes/2026-10-31-who-produces-draftees.qmd` from `vignettes/_post-template.qmd`, modelled on `vignettes/2026-10-31-conferences-landscape.qmd` (same setup/load idioms, tier colors, `fmt`/`pct`, registry, girafe defaults).

**Population:** `team_draft`, credit seasons 2013–2025 (≈ classes 2014–2026), FBS teams individually; FCS and below appears only as a tier aggregate with the incomplete-roster caveat. Exclude "Position not recorded" from position rankings (report its count). Conference = credit-season conference for conference rates; for within-conference school comparisons, group schools by their **2025 conference** (state it).

**Rates:** draft rate = drafted / eligible; UDFA rate = UDFAs / eligible (non-OL caveat: OL UDFAs undercounted). Expected draftees = FBS rate for the position group × the school's eligible players at that position, summed over positions (so a school heavy in high-rate positions is not credited for it). "Above expected" = observed − expected, and the shrunk rate via `shrink_rate()` (group = 2025 conference for 3.4; group = position for 3.5). Introduce the idea in plain words before naming it ("small samples are pulled toward the group average; this is called empirical Bayes shrinkage").

**Sections (headings are draft assertions; reword to the numbers):**

- 1 Introduction: one or two sentences, recurring cast where natural (Burrow: LSU, Cam Ward: Miami, Jordan Travis: Florida State; Josh Allen: Wyoming as the G5 counterpoint). No expectation lines (descriptive post), except the fan-nickname check is framed as questions answered in 3.5 without verdict emojis.
- 2.1 Terms table: eligible player (a player whose college career ended and who had 3+ roster seasons, or was drafted, or signed undrafted), draft rate, UDFA, UDFA rate, expected draftees, shrunk rate, tier, conference, position group.
- 3.1 *Power-conference players are drafted at about five times the Group of 5 rate.* Table: tier and conference counts and rates. Explanatory: ordered horizontal bars of conference draft rate, SEC highlighted, tier colors. Exploratory: ggiraph conference × credit season rates (line or tile) with tooltips (drafted / eligible).
- 3.2 *Undrafted signings are spread far more evenly than draft picks.* Table: tier and conference UDFA vs draft rate. Explanatory: dumbbell per conference (draft vs UDFA rate) with the narrowing highlighted. Exploratory: every FBS school, draft rate (x) vs UDFA rate (y), team colors, tooltip with counts; name the UDFA-heavy schools.
- 3.3 *Each position's draft rate depends on conference.* Table: position group × tier rates. Explanatory: heatmap conference × position group (rate), leader cell per position outlined. Exploratory: ggiraph heatmap of the same at finer grain (conference × position × counts in tooltip) or school × position for one conference selector-free view.
- 3.4 *Within every conference a few schools draft far above expected.* Table: top 15 FBS schools by draftees above expected (observed, expected, raw rate, shrunk rate). Explanatory: dot plot per 2025 conference of shrunk rate, conference average line, leader labelled. Exploratory: every FBS school, raw vs shrunk rate, point size = eligible, tooltip.
- 3.5 *Position "U" titles: the data's leaders, and which nicknames hold.* Table: per position group, top school by draftees above expected (and by count), plus a nickname rows table (nickname, school that claims it, that school's rank at the position, data leader). Explanatory: small multiples, top 5 schools per position by above-expected, nickname school highlighted. Exploratory: ggiraph every school × position above-expected.
- 4 Summary: one sentence + findings ledger (Finding / Evidence, inline pinned numbers).
- 5 Discussion: callout-important blocks (e.g. concentration is mostly a Power-conference story; UDFAs are the broader pipeline) + short caveats paragraph (credit to final team, transfers credit the last stop; eligibility proxy; OL UDFAs undercounted; FCS rosters incomplete; credit seasons ≈ draft classes; 2025 conference grouping).
- YAML: title one declarative sentence (no colon) == VignetteIndexEntry; description = the headline finding; followups (Post 3 win %; position mix vs program; recruiting-adjusted production; FCS completeness); author "AI directed by Nick Giangreco"; `freeze: auto`.

**Rules:** every number in prose/headings/captions/annotations computed and pinned with `stopifnot()` (exact values, ids from the registry for named players); no em dashes; reader-facing labels; team colors via `teams`; `theme_cfb2nfl()`; one or two sentences per section; loading chunks `include: false`.

- [ ] **Step 1:** Explore the numbers (Rscript against `data/cfb2nfl.duckdb`), confirm the facts above, check nickname claims.
- [ ] **Step 2:** Write sections 1–3.2, render standalone (`CFB2NFL_ROOT=$(pwd) quarto render vignettes/2026-10-31-who-produces-draftees.qmd`), commit.
- [ ] **Step 3:** Write 3.3–3.5, render, commit.
- [ ] **Step 4:** Summary, Discussion, YAML; final render; check figures as PNGs; grep for "—"; commit.

## Task C: Ship

- [ ] NEWS entry (post + `shrink_rate()`), `air format . --check`, `devtools::test()`, `devtools::check()` (0/0), mark Post 2 done in `plans/conferences-teams.md`, branch `feat/post2-producers`, PR via `gh` R package, merge after CI + user approval.
