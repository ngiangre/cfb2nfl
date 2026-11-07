# A minimal post that follows every mechanical rule; each test breaks one.
good_post <- c(
  "---",
  'title: "Most eligible seasons end without a draft pick"',
  'date: "2026-11-07"',
  'description: "Fewer than five in every hundred eligible seasons end in a pick."',
  "followups:",
  '  - "Does the rate differ by position?"',
  "author:",
  '  - "AI directed by Nick Giangreco"',
  "freeze: auto",
  "vignette: >",
  "  %\\VignetteIndexEntry{Most eligible seasons end without a draft pick}",
  "  %\\VignetteEngine{quarto::html}",
  "  %\\VignetteEncoding{UTF-8}",
  "---",
  "",
  "```{r}",
  "#| label: setup",
  "#| output: false",
  "x <- 1",
  "```",
  "",
  "## 1. Introduction",
  "",
  "## 2. Data",
  "",
  "### 2.1 Every season ends in one status",
  "",
  "```{r}",
  "#| label: terms",
  "tibble::tibble(a = 1) |>",
  '  knitr::kable(caption = "Terms.")',
  "```",
  "",
  "## 3. Results",
  "",
  "### 3.1 The draft is rare",
  "",
  "*Expectation: the draft is rare,",
  "under five percent of seasons.* \u2705",
  "",
  "## 4. Summary",
  "",
  "## 5. Discussion",
  "",
  "::: {.callout-important}",
  "A point.",
  ":::"
)

post_rules <- function(lines) {
  path <- withr::local_tempfile(fileext = ".qmd")
  writeLines(lines, path, useBytes = TRUE)
  check_post_style(path)$rule
}

edit_post <- function(pattern, replacement, lines = good_post) {
  i <- grep(pattern, lines)[1]
  lines[i] <- replacement
  lines
}

test_that("a post that follows the style passes", {
  expect_identical(post_rules(good_post), character())
})

test_that("front-matter rules are enforced", {
  expect_true(
    "title" %in%
      post_rules(edit_post("^title:", 'title: "Draft odds: a look"'))
  )
  expect_true(
    "index_entry" %in%
      post_rules(edit_post(
        "VignetteIndexEntry",
        "  %\\VignetteIndexEntry{An older title}"
      ))
  )
  expect_true(
    "description" %in% post_rules(good_post[!grepl("^description:", good_post)])
  )
  no_followups <- good_post[!grepl("^followups:|Does the rate", good_post)]
  expect_true("followups" %in% post_rules(no_followups))
  no_author <- good_post[!grepl("^author:|AI directed", good_post)]
  expect_true("author" %in% post_rules(no_author))
  expect_true(
    "freeze" %in% post_rules(edit_post("^freeze:", "freeze: true"))
  )
})

test_that("the setup chunk must be single and first", {
  no_setup <- edit_post("label: setup", "#| label: load")
  expect_true("setup_chunk" %in% post_rules(no_setup))
  second <- edit_post("label: terms", "#| label: setup")
  expect_true("setup_chunk" %in% post_rules(second))
})

test_that("chunk rules are enforced", {
  expect_true(
    "include_false" %in%
      post_rules(edit_post("^#\\| output: false", "#| include: false"))
  )
  expect_true(
    "stopifnot" %in% post_rules(edit_post("^x <- 1", "stopifnot(x == 1)"))
  )
  expect_true(
    "pie_chart" %in%
      post_rules(edit_post("^x <- 1", "p <- p + coord_polar(theta = 'y')"))
  )
  expect_true(
    "kable_caption" %in%
      post_rules(edit_post("knitr::kable", "  knitr::kable()"))
  )
})

test_that("kable captions are read through pipes and empty arguments", {
  ok <- parse(text = "d[, 1] |> kable(caption = 'A.')")
  bad <- parse(text = "d[, 1] |> kable(digits = 1)")
  expect_identical(n_uncaptioned_kable(ok), 0L)
  expect_identical(n_uncaptioned_kable(bad), 1L)
})

test_that("prose rules are enforced", {
  expect_true(
    "em_dash" %in%
      post_rules(edit_post("^A point", "A point \u2014 then more."))
  )
  expect_true(
    "sections" %in% post_rules(good_post[good_post != "## 4. Summary"])
  )
  expect_true(
    "assertion_heading" %in%
      post_rules(edit_post("^### 3.1", "### The draft is rare"))
  )
  expect_true(
    "expectation_verdict" %in%
      post_rules(edit_post("under five", "under five percent of seasons.*"))
  )
  expect_true(
    "discussion_callout" %in%
      post_rules(edit_post("callout-important", "::: {.callout-note}"))
  )
})

test_that("every dated post in vignettes/ follows the style", {
  dir <- test_path("..", "..", "vignettes")
  # vignettes/ is .Rbuildignored, so R CMD check runs without it; the
  # post-style CI job and devtools::test() run this against the checkout.
  skip_if_not(dir.exists(dir), "vignettes/ not in this build")
  bad <- check_posts_style(dir)
  expect(
    nrow(bad) == 0L,
    paste(
      c(
        "Post style violations:",
        sprintf("%s:%s [%s] %s", bad$file, bad$line, bad$rule, bad$message)
      ),
      collapse = "\n"
    )
  )
})
