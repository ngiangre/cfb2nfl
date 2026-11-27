# Card style checks (feature F25). Each test builds a throwaway checkout with
# the card registries, a fresh thumbnail for the good card, and breaks one
# rule.

good_card_lines <- function(id = "demo") {
  c(
    "---",
    'title: "Which positions are drafted most?"',
    paste0("image: card-thumbs/", id, ".png"),
    'image-alt: "Bar chart of NFL draft picks by position since 2013, wide receivers first."',
    'categories: ["Topic: Draft outcomes", "Position: All positions", "Question: Draft chance by position"]',
    "status: sketch",
    "graduated_to: null",
    "terms: [eligible-season]",
    "followups:",
    '  - text: "Does the order change by tier?"',
    '    link: "Question: Draft chance by position"',
    '  - text: "Who forecasts it?"',
    '    link: "F17"',
    "---",
    "",
    "```{r}",
    "#| label: setup",
    "#| output: false",
    'con <- DBI::dbConnect(duckdb::duckdb(), "data/cfb2nfl.duckdb")',
    "release <- data_release_date()",
    "```",
    "",
    "```{r}",
    "#| label: figure",
    "p <- ggplot2::ggplot() +",
    '  ggplot2::labs(title = "Draft picks by position", caption = card_caption(release))',
    paste0('card_thumbnail(p, "', id, '", release = release)'),
    "card_interactive(p)",
    "```",
    "",
    "```{r}",
    "#| label: card-footer",
    "#| output: asis",
    "card_footer()",
    "```"
  )
}

local_card_root <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(root, "vignettes"))
  dir.create(file.path(root, "inst", "cards"), recursive = TRUE)
  dir.create(file.path(root, "product"))
  dir.create(file.path(root, "R"))
  writeLines(
    c(
      "Topic: [Draft outcomes, Movement]",
      "Position: [All positions, QB]"
    ),
    file.path(root, "inst", "cards", "tags.yml")
  )
  writeLines(
    c(
      "- tag: Draft chance by position",
      '  question: "After each season, what is a player\'s chance of being drafted, by position?"',
      "  status: in progress",
      "- tag: Assistant coaches",
      '  question: "Do coordinators matter?"',
      "  status: not answerable",
      '  reason: "CFBD lists head coaches only."'
    ),
    file.path(root, "inst", "cards", "questions.yml")
  )
  writeLines(
    c(
      "eligible-season:",
      "  label: Eligible season",
      '  definition: "A college season after which the player could be drafted."'
    ),
    file.path(root, "inst", "cards", "terms.yml")
  )
  writeLines(
    c("### F17 · Per-position draft forecast", "### F25 · Cards"),
    file.path(root, "product", "features.md")
  )
  writeLines(
    "helper_fn <- function(x) {\n  x + 1\n}",
    file.path(root, "R", "helpers.R")
  )
  root
}

# Write a card and (unless `thumb = FALSE`) a fresh thumbnail for it.
write_good_card <- function(
  root,
  lines = good_card_lines(),
  id = "demo",
  thumb = TRUE
) {
  path <- file.path(root, "vignettes", paste0("card-", id, ".qmd"))
  writeLines(lines, path)
  if (thumb) {
    card_thumbnail(
      ggplot2::ggplot(),
      id,
      card = path,
      release = as.Date("2026-11-25"),
      dir = file.path(root, "vignettes", "card-thumbs"),
      root = root
    )
  }
  path
}

card_rules <- function(root, path, ...) {
  check_card_style(path, root = root, ...)$rule
}

edit_lines <- function(lines, pattern, replacement) {
  sub(pattern, replacement, lines)
}

test_that("function hashes ignore comments and layout but not code", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  card <- write_good_card(
    root,
    c(good_card_lines()[1:13], "", "```{r}", "y <- helper_fn(1)", "```"),
    thumb = FALSE
  )
  h1 <- card_hashes(card, root = root)$functions$helper_fn
  writeLines(
    "# a comment\nhelper_fn <- function(x) { x   + 1 }",
    file.path(root, "R", "helpers.R")
  )
  expect_equal(card_hashes(card, root = root)$functions$helper_fn, h1)
  writeLines(
    "helper_fn <- function(x) x + 2",
    file.path(root, "R", "helpers.R")
  )
  expect_false(identical(
    card_hashes(card, root = root)$functions$helper_fn,
    h1
  ))
})

test_that("a card that follows every rule passes", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  path <- write_good_card(root)
  bad <- check_card_style(path, root = root)
  expect_equal(nrow(bad), 0L, info = paste(bad$rule, bad$message))
})

test_that("front matter rules catch a missing question, image, alt text and status", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- good_card_lines()
  p <- write_good_card(
    root,
    edit_lines(lines, "drafted most\\?", "drafted most")
  )
  expect_true("title" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    edit_lines(lines, "card-thumbs/demo", "card-thumbs/other")
  )
  expect_true("image" %in% card_rules(root, p))
  p <- write_good_card(root, edit_lines(lines, '"Bar chart.*"', '"A chart."'))
  expect_true("image_alt" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    edit_lines(lines, "status: sketch", "status: done")
  )
  expect_true("status" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    edit_lines(lines, "status: sketch", "status: graduated")
  )
  expect_true("graduated_to" %in% card_rules(root, p))
})

test_that("tags must be approved and question tags registered", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- good_card_lines()
  p <- write_good_card(
    root,
    edit_lines(lines, "Topic: Draft outcomes", "Topic: Drafts")
  )
  expect_true("tags" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    edit_lines(
      lines,
      '"Question: Draft chance by position"\\]',
      '"Question: Unknown"]'
    )
  )
  expect_true("question_tag" %in% card_rules(root, p))
})

test_that("terms must come from the glossary", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  p <- write_good_card(
    root,
    edit_lines(
      good_card_lines(),
      "terms: \\[eligible-season\\]",
      "terms: [hazard]"
    )
  )
  expect_true("terms" %in% card_rules(root, p))
})

test_that("every follow-up links to a registered question or a feature", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- good_card_lines()
  p <- write_good_card(root, edit_lines(lines, 'link: "F17"', 'link: "F99"'))
  expect_true("followup_link" %in% card_rules(root, p))
  p <- write_good_card(root, lines[!grepl('link: "F17"', lines)])
  expect_true("followup_link" %in% card_rules(root, p))
})

test_that("a card must save a thumbnail, show it interactively, date it and read the DuckDB", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- good_card_lines()
  p <- write_good_card(
    root,
    lines[!grepl("^card_thumbnail", lines)],
    thumb = FALSE
  )
  expect_true("no_figure" %in% card_rules(root, p))
  p <- write_good_card(root, lines[!grepl("^card_interactive", lines)])
  expect_true("no_interactive" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    edit_lines(lines, ", caption = card_caption\\(release\\)", "")
  )
  expect_true("release_date" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    edit_lines(lines, "data/cfb2nfl.duckdb", "data/other.duckdb")
  )
  expect_true("duckdb" %in% card_rules(root, p))
})

test_that("a missing or stale thumbnail fails; a newer data release is only a note", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  p <- write_good_card(root, thumb = FALSE)
  expect_true("thumbnail" %in% card_rules(root, p))

  p <- write_good_card(root)
  writeLines(
    edit_lines(
      good_card_lines(),
      "Draft picks by position",
      "Picks by position"
    ),
    p
  )
  bad <- check_card_style(p, root = root)
  expect_equal(bad$severity[bad$rule == "thumbnail"], "error")

  p <- write_good_card(root)
  bad <- check_card_style(p, root = root, release = as.Date("2026-12-02"))
  expect_equal(bad$rule, "thumbnail")
  expect_equal(bad$severity, "note")
})

test_that("figure text carries no typed numbers and no column names", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- good_card_lines()
  p <- write_good_card(
    root,
    edit_lines(lines, "Draft picks by position", "Draft picks since 2013")
  )
  expect_true("numeric_title" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    edit_lines(lines, "Draft picks by position", "picks by position_group")
  )
  expect_true("column_name" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    append(
      lines,
      'knitr::kable(d, caption = "Picks.")',
      after = which(lines == "card_interactive(p)")
    )
  )
  expect_true("column_name" %in% card_rules(root, p))
})

test_that("typed numbers and column names are caught inside paste(), ggtitle() and col.names", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- good_card_lines()
  fig <- which(lines == "card_interactive(p)")
  p <- write_good_card(
    root,
    edit_lines(lines, '"Draft picks by position"', 'paste("Top 10 schools", y)')
  )
  expect_true("numeric_title" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    append(
      lines,
      'p <- p + ggplot2::ggtitle("The 2024 class")',
      after = fig - 1
    )
  )
  expect_true("numeric_title" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    append(
      lines,
      'knitr::kable(d, caption = "Picks.", col.names = c("draft_year", "n"))',
      after = fig
    )
  )
  expect_true("column_name" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    append(
      lines,
      'knitr::kable(d, caption = "Picks.", col.names = c("Draft year", "Picks"))',
      after = fig
    )
  )
  expect_false("column_name" %in% card_rules(root, p))
})

test_that("the footer chunk prints the card footer as markdown", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- good_card_lines()
  p <- write_good_card(root, lines[lines != "#| output: asis"])
  expect_true("footer" %in% card_rules(root, p))
  p <- write_good_card(root, lines[lines != "card_footer()"])
  expect_true("footer" %in% card_rules(root, p))
})

test_that("amber highlights, which read as quarterbacks, are flagged", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- good_card_lines()
  fig <- which(lines == "card_interactive(p)")
  p <- write_good_card(
    root,
    append(lines, 'claim_fill <- "#B45309"', after = fig - 1)
  )
  expect_true("palette" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    append(lines, 'tier <- c(g5 = "#f59e0b")', after = fig - 1)
  )
  expect_true("palette" %in% card_rules(root, p))
})

test_that("an unclosed code chunk is reported, not a crash", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- good_card_lines()
  p <- write_good_card(root, lines[-length(lines)])
  rules <- card_rules(root, p)
  expect_true("footer" %in% rules)
})

test_that("stock palettes that reuse the outcome colours are flagged; sequential ones are not", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- good_card_lines()
  fig <- which(lines == "card_interactive(p)")
  p <- write_good_card(
    root,
    append(lines, "p <- p + ggplot2::scale_fill_viridis_c()", after = fig - 1)
  )
  expect_true("palette" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    append(
      lines,
      'p <- p + ggplot2::scale_colour_brewer(palette = "Dark2")',
      after = fig - 1
    )
  )
  expect_true("palette" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    append(
      lines,
      'p <- p + ggplot2::scale_fill_brewer(palette = "YlGnBu")',
      after = fig - 1
    )
  )
  expect_false("palette" %in% card_rules(root, p))
})

test_that("a card carries no narrative prose", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- append(
    good_card_lines(),
    c("", "Receivers lead because teams pass more."),
    after = 14
  )
  p <- write_good_card(root, lines)
  expect_true("prose" %in% card_rules(root, p))
})

test_that("a card does not redefine a shared helper", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- good_card_lines()
  p <- write_good_card(
    root,
    append(
      lines,
      "pct <- function(x) paste0(100 * x, \"%\")",
      after = which(lines == "#| label: figure")
    )
  )
  expect_true("helper_redefined" %in% card_rules(root, p))
})

test_that("em dashes, pie charts and uncaptioned tables are flagged", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  lines <- good_card_lines()
  p <- write_good_card(
    root,
    edit_lines(lines, "Draft picks by position", "Draft picks — by position")
  )
  expect_true("em_dash" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    edit_lines(
      lines,
      "^card_interactive\\(p\\)",
      "card_interactive(p + ggplot2::coord_polar())"
    )
  )
  expect_true("pie_chart" %in% card_rules(root, p))
  p <- write_good_card(
    root,
    append(
      lines,
      "knitr::kable(d, col.names = \"Picks\")",
      after = which(lines == "card_interactive(p)")
    )
  )
  expect_true("kable_caption" %in% card_rules(root, p))
})

test_that("a published card cannot be renamed or deleted without an alias", {
  skip_if_not_installed("ggplot2")
  root <- local_card_root()
  write_good_card(root)
  writeLines(
    c(
      "- post: 2026-10-24-outcome-prevalence",
      "  section: '3.1'",
      "  card: gone"
    ),
    file.path(root, "inst", "cards", "migration.yml")
  )
  bad <- check_cards_style(root = root)
  expect_true("published_card" %in% bad$rule)

  lines <- append(good_card_lines(), "aliases: [card-gone.html]", after = 1)
  write_good_card(root, lines)
  bad <- check_cards_style(root = root)
  expect_false("published_card" %in% bad$rule)
})

test_that("new_card scaffolds a sketch card from the template", {
  root <- local_card_root()
  writeLines(
    c(
      "---",
      'title: "{{question}}"',
      "image: card-thumbs/{{id}}.png",
      "status: sketch",
      "---"
    ),
    file.path(root, "vignettes", "_card-template.qmd")
  )
  path <- new_card("transfer-rate", root = root)
  expect_equal(path, file.path(root, "vignettes", "card-transfer-rate.qmd"))
  expect_true(any(grepl(
    "card-thumbs/transfer-rate.png",
    readLines(path),
    fixed = TRUE
  )))
  expect_error(new_card("transfer-rate", root = root), "exists")
  expect_error(new_card("Transfer Rate", root = root), "lowercase")
})

test_that("card_footer shows the release date, question status and linked follow-ups", {
  root <- local_card_root()
  dir.create(file.path(root, "data"))
  write_release_stamp(as.Date("2026-11-25"), file.path(root, "data"))
  lines <- edit_lines(
    good_card_lines(),
    '"Question: Draft chance by position"\\]',
    '"Question: Assistant coaches"]'
  )
  path <- write_good_card(root, lines, thumb = FALSE)
  out <- card_footer(path, root = root)
  expect_match(out, "2026-11-25", all = FALSE)
  expect_match(out, "CFBD lists head coaches only.", fixed = TRUE, all = FALSE)
  expect_match(out, "#category=", fixed = TRUE, all = FALSE)
  expect_match(out, "features.md", fixed = TRUE, all = FALSE)
  expect_match(
    out,
    "A college season after which the player could be drafted.",
    fixed = TRUE,
    all = FALSE
  )
})

test_that("every card in vignettes/ follows the style", {
  dir <- test_path("..", "..", "vignettes")
  skip_if_not(dir.exists(dir), "vignettes/ not in this build")
  bad <- check_cards_style(root = test_path("..", ".."))
  bad <- bad[bad$severity == "error", ]
  expect(
    nrow(bad) == 0L,
    paste(
      c(
        "Card style violations:",
        sprintf("%s:%s [%s] %s", bad$file, bad$line, bad$rule, bad$message)
      ),
      collapse = "\n"
    )
  )
})

test_that("every package a card calls is declared in DESCRIPTION", {
  # The site build installs only DESCRIPTION's packages, so an undeclared one
  # breaks the deploy (forcats did).
  root <- test_path("..", "..")
  skip_if_not(
    dir.exists(file.path(root, "vignettes")),
    "vignettes/ not in this build"
  )
  d <- read.dcf(
    file.path(root, "DESCRIPTION"),
    fields = c("Imports", "Suggests")
  )
  declared <- trimws(sub(
    "[(].*",
    "",
    unlist(strsplit(paste(d, collapse = ","), ","))
  ))
  base_pkgs <- rownames(installed.packages(priority = "base"))
  cards <- list.files(
    file.path(root, "vignettes"),
    "^card-.*[.]qmd$",
    full.names = TRUE
  )
  code <- unlist(lapply(cards, card_code))
  code <- sub("#.*$", "", code)
  used <- c(
    unlist(regmatches(
      code,
      gregexpr("[A-Za-z][A-Za-z0-9.]*(?=::)", code, perl = TRUE)
    )),
    sub(
      ".*library[(]([A-Za-z0-9.]+)[)].*",
      "\\1",
      grep("library[(]", code, value = TRUE)
    )
  )
  missing <- setdiff(unique(trimws(used)), c(declared, base_pkgs, "cfb2nfl"))
  expect(
    length(missing) == 0L,
    paste("Undeclared packages:", paste(missing, collapse = ", "))
  )
})
