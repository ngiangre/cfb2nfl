features_md <- c(
  "## G1 · Answer",
  "",
  "### F07 · Posts: who reaches the draft",
  "",
  "- **Goals:** G1 · **Personas:** P1 · **Status:** shipped",
  "- **Tasks:**",
  "<!-- tasks F07 -->",
  "- [ ] stale line",
  "<!-- /tasks -->",
  "",
  "### F04 · Play-by-play",
  "",
  "- **Goals:** G1, C2 · **Personas:** P1, P2 · **Status:** shipped",
  "- **Tasks:**",
  "<!-- tasks F04 -->",
  "<!-- /tasks -->"
)

test_that("feature_ids_in() reads Feature lines in bodies and comments", {
  expect_equal(feature_ids_in("Some text\nFeature: F19 (criteria 1, 3)"), "F19")
  expect_equal(
    feature_ids_in(c("Features: F04, F21", "Feature: F04")),
    c("F04", "F21")
  )
  expect_equal(feature_ids_in("  feature: F13"), "F13")
  # A mention mid-sentence is not a Feature line.
  expect_equal(feature_ids_in("see Feature F13 for context"), character())
  expect_equal(feature_ids_in(NA_character_), character())
})

test_that("goal_labels() maps goals and constraints to issue labels", {
  expect_equal(goal_labels("G1, C2"), c("goal:G1", "constraint:budget"))
  expect_equal(goal_labels("C1"), "constraint:trust")
  expect_error(goal_labels("G9, C7"), "C7")
})

test_that("feature_goals() reads each card's Goals line", {
  out <- feature_goals(features_md)
  expect_equal(out$feature, c("F07", "F04"))
  expect_equal(out$goals, c("G1", "G1, C2"))
})

test_that("task_line() renders a checklist item, ticked when closed", {
  expect_equal(
    task_line(70, "Explorer", "https://x/70", closed = TRUE, is_pr = FALSE),
    "- [x] [#70](https://x/70) Explorer"
  )
  expect_equal(
    task_line(91, "Game flow", "https://x/91", closed = FALSE, is_pr = TRUE),
    "- [ ] [PR #91](https://x/91) Game flow"
  )
})

test_that("splice_tasks() replaces each block and empties untasked ones", {
  out <- splice_tasks(features_md, list(F04 = c("- [x] [#44](u) Plays")))
  f04 <- which(out == "<!-- tasks F04 -->")
  expect_equal(out[f04 + 1], "- [x] [#44](u) Plays")
  expect_equal(out[f04 + 2], "<!-- /tasks -->")
  # F07 had a stale line and no tasks now: the block is emptied.
  f07 <- which(out == "<!-- tasks F07 -->")
  expect_equal(out[f07 + 1], "<!-- /tasks -->")
  # Text outside the markers is untouched.
  expect_equal(out[1:6], features_md[1:6])
})

test_that("splice_tasks() refuses tasks for a feature with no block", {
  expect_error(splice_tasks(features_md, list(F99 = "- [ ] x")), "F99")
})
