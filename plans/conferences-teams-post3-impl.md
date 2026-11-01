# Post 3 (do good teams produce more draftees?) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish Post 3 of the series in `plans/conferences-teams.md`, testing the user's one expectation, *teams that win more produce more draftees*, within tier, with SP+ as a check, named over- and under-producers, persistence, a direction check, and a transfer sensitivity check.

**Architecture:** Post only; no pipeline changes. Reads `team_season`, `team_draft`, `roster`, `picks`, `teams`, `outcomes` from the DuckDB bundle; calls `exit_cohort()` / `reused_ids()` (package functions via `pkgload::load_all`) for the transfer check.

**Tech Stack:** R, dplyr, stats::glm, Quarto, ggplot2 + ggiraph, knitr::kable.

**Read:** `plans/conferences-teams.md` (Post 3), Posts 1 and 2 (`vignettes/2026-10-31-conferences-landscape.qmd`, `vignettes/2026-10-31-who-produces-draftees.qmd`) for idioms and tone, AGENTS.md blog style + writing critiques, decision 0033, `inst/dict/team_*.yml`.

---

## Facts measured 2026-10-31

School unit: FBS schools; win % = games-weighted mean over FBS seasons 2010–2025 (completed games); draft rate = drafted / eligible over credit seasons 2013–2025; tier = the tier the school held in most seasons.

- 137 schools (65 Power, 72 Group of 5). Correlation of win % with draft rate: Power r = 0.82 (Spearman 0.80), Group of 5 0.46; pooled 0.66 (inflated by the tier gap). SP+ instead of win %: Power 0.87, Group of 5 0.63.
- Power over-producers vs a linear fit on win %: Alabama, Florida, LSU, Kansas (artifact of the linear fit at low win %; use the binomial fit below), Miami, Ohio State. Under-producers: Oklahoma State, Kansas State, TCU, Michigan State, Wisconsin, Duke.
- Team-season level (Power): r = 0.49 between a season's win % and the draft rate of players whose final season it was.
- Windows A = 2013–2017, B = 2019–2023, Power schools in Power both windows (n = 65): win A → draft rate B r = 0.57; draft rate A → win B r = 0.57 (direction not separable); draft-rate persistence 0.68; win persistence 0.61.

## Method decisions

- **Expectation tested:** *Teams that win more produce more draftees.* One expectation, with verdict emoji (✅ / ❌) after the italic statement in its Results section and in the Summary ledger. Judge it within tier: the verdict is ✅ if the within-tier association is clearly positive in both tiers (state strength per tier); say plainly that it is much stronger for Power schools.
- **Fit:** per tier, binomial GLM `cbind(drafted, eligible - drafted) ~ win_pct` at the school level (weights implicit). Expected draftees = fitted rate × eligible; over/under-producers = observed − expected (named, pinned). Introduce in plain words ("for a school with this record, how many draftees would we expect") before naming logistic regression. Report correlation as "r" only after explaining it ("0 means no relationship, 1 a perfect line").
- **SP+ check:** same correlation and fit with mean SP+ (FBS only); explain SP+ in one plain sentence (a rating that adjusts each game for the opponent's strength).
- **Persistence and direction:** windows A/B as above; describe the symmetric cross-correlations plainly as "the data cannot say which comes first", no causal language.
- **Transfer sensitivity:** in the post, `exits <- exit_cohort(roster, picks, udfa_ids, reused_ids(roster))`; flag a drafted or eligible exit as a transfer-in if the player has a roster season at a different team before their credit season; recompute school draft rates on non-transfers and the within-tier correlations; report both (pin). Note the late-window rise of Group of 5 → Power transfer draftees from Post 2.
- **Recurring cast:** Burrow (transfer Ohio State → LSU, 2019 national title season: an over-producer story), Cam Ward (Miami 2024), Jordan Travis (Florida State 2023 13-0), Josh Allen (Wyoming); ids from a registry, every fact pinned.

## Task: Post 3

**Files:** Create `vignettes/2026-10-31-winning-and-draftees.qmd` from `vignettes/_post-template.qmd`.

**Sections (draft assertions; reword to the numbers):**
- 1 Introduction: one or two sentences linking Posts 1–2; the expectation as an italic line.
- 2.1 Terms table: win %, SP+, draft rate, eligible player (same definition as Post 2), expected draftees, correlation (r), over-/under-producer, transfer-in.
- 3.1 *Expectation: teams that win more produce more draftees.* ✅/❌ — within each tier, school win % tracks draft rate. Table: per tier n, r (win %), r (SP+). Explanatory: scatter win % vs draft rate, colored by tier, binomial fit line per tier, the pooled-vs-within message highlighted. Exploratory: ggiraph every school, team colors, tooltip (record, rate, drafted/eligible, SP+).
- 3.2 *A few programs draft far more than their record predicts, and some win without draftees.* Table: top 5 over and under per tier (observed, expected, difference). Explanatory: diverging bars of observed − expected, named, team colors. Exploratory: every school's observed vs expected.
- 3.3 *SP+ tells the same story, a little more tightly.* Single fact: table + one figure (SP+ vs draft rate, Power and G5).
- 3.4 *A school's draft rate persists, and winning and drafting rise together.* Table: the four window correlations. Explanatory: scatter draft rate A vs B with diagonal, outliers named. Exploratory: per-school A→B arrows or slope chart with tooltips.
- 3.5 *Crediting transfers to their final school changes little / changes X.* (reword to result) Table: correlations with and without transfer-ins per tier; transfer-in draftees by class. Explanatory: transfer-in draftees per class highlighting the late rise. Exploratory: per-school rate with vs without transfer-ins.
- 4 Summary: one sentence + expectation ledger (Expectation / Verdict / Evidence).
- 5 Discussion: callout-important (association, not cause; talent from recruiting likely drives both — a followup), short caveats paragraph.
- YAML: declarative title (no colon) == VignetteIndexEntry; one-sentence finding description; followups (recruiting talent as a common cause; coach effects; season-level timing; NFL success by program); author "AI directed by Nick Giangreco"; freeze: auto.

**Rules:** every stated number computed and pinned exactly with `stopifnot()`; named players by registry id; neutral pronouns (they/their) for players in general; no em dashes; reader-facing labels; team colors from `teams`; `theme_cfb2nfl()`; one or two sentences per section; table → explanatory → exploratory ggiraph; loaders `include: false`.

- [ ] Step 1: Explore and confirm the facts (Rscript against `data/cfb2nfl.duckdb`).
- [ ] Step 2: Sections 1–3.2, render (`CFB2NFL_ROOT=$(pwd) quarto render vignettes/2026-10-31-winning-and-draftees.qmd`), commit.
- [ ] Step 3: Sections 3.3–3.5, render, commit.
- [ ] Step 4: Summary, Discussion, YAML; final render; PNG figure checks; grep "—"; commit.

## Ship

- [ ] NEWS entry, mark Post 3 done in `plans/conferences-teams.md`, `air format . --check`, `devtools::test()`, `devtools::check()`, branch `feat/post3-winning`, PR via `gh` R package, merge after CI + user approval.
