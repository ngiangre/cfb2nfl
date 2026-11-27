# Card helpers (feature F25): the release date, the card theme, thumbnails
# and their freshness sidecar.

write_card <- function(
  dir,
  code = "p <- ggplot2::ggplot()",
  front = "title: \"Q?\""
) {
  path <- file.path(dir, "card-test.qmd")
  writeLines(
    c("---", front, "---", "", "```{r}", code, "```", "", "Some text."),
    path
  )
  path
}

test_that("data_release_date reads the stamp written when the release was downloaded", {
  dir <- withr::local_tempdir()
  write_release_stamp(as.POSIXct("2026-11-25 20:59:20", tz = "UTC"), dir)
  expect_equal(data_release_date(dir), as.Date("2026-11-25"))
})

test_that("data_release_date errors with a pointer when no release was downloaded", {
  dir <- withr::local_tempdir()
  expect_error(data_release_date(dir), "pull-data")
})

test_that("card paths resolve to vignettes/ in the checkout, not the render copy", {
  withr::local_envvar(CFB2NFL_ROOT = "/repo")
  expect_equal(card_root(), "/repo")
  expect_equal(
    card_source("/repo/_quarto/vignettes/card-x.qmd"),
    file.path("/repo", "vignettes", "card-x.qmd")
  )
  expect_equal(card_thumb_dir(), file.path("/repo", "vignettes", "card-thumbs"))
})

test_that("card_caption names the source and the release date", {
  expect_equal(
    card_caption(as.Date("2026-11-25"), source = "CFBD"),
    "Data: CFBD | data release 2026-11-25"
  )
})

test_that("theme_card builds on the project theme with a larger base size", {
  skip_if_not_installed("ggplot2")
  th <- theme_card()
  expect_s3_class(th, "theme")
  expect_gt(th$text$size, theme_cfb2nfl()$text$size)
})

test_that("card_code keeps only the R chunks of a card", {
  dir <- withr::local_tempdir()
  path <- write_card(dir, code = c("x <- 1", "y <- fmt(x)"))
  expect_equal(card_code(path), c("x <- 1", "y <- fmt(x)"))
})

test_that("card_functions finds the package functions a card calls, transitively", {
  dir <- withr::local_tempdir()
  # scale_fill_team() calls team_color_values(), which the card never names.
  path <- write_card(
    dir,
    code = c("s <- scale_fill_team(teams)", "z <- pct(0.5)")
  )
  fns <- card_functions(path)
  expect_true(all(c("scale_fill_team", "team_color_values", "pct") %in% fns))
  expect_false("ggplot" %in% fns)
})

test_that("card_thumbnail saves the PNG and a sidecar of hashes", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("ragg")
  dir <- withr::local_tempdir()
  card <- write_card(dir, code = "z <- pct(0.5)")
  p <- ggplot2::ggplot(data.frame(x = 1:3, y = 1:3), ggplot2::aes(x, y)) +
    ggplot2::geom_point()
  out <- card_thumbnail(
    p,
    "test",
    card = card,
    release = as.Date("2026-11-25"),
    dir = file.path(dir, "card-thumbs")
  )
  expect_true(file.exists(out))
  side <- jsonlite::read_json(sub("[.]png$", ".json", out))
  expect_equal(side$release, "2026-11-25")
  expect_true(nzchar(side$code_hash))
  expect_true("pct" %in% names(side$functions))
})

test_that("card_freshness reports fresh, then stale code, R and data changes", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("ragg")
  dir <- withr::local_tempdir()
  thumbs <- file.path(dir, "card-thumbs")
  card <- write_card(dir, code = "z <- pct(0.5)")
  p <- ggplot2::ggplot()
  rel <- as.Date("2026-11-25")
  card_thumbnail(p, "test", card = card, release = rel, dir = thumbs)

  expect_equal(card_freshness(card, "test", dir = thumbs)$status, "fresh")
  expect_equal(
    card_freshness(card, "test", dir = thumbs, release = rel)$status,
    "fresh"
  )
  expect_equal(
    card_freshness(card, "test", dir = thumbs, release = rel + 7)$status,
    "stale_data"
  )

  # Front matter and prose edits do not stale the thumbnail; code edits do.
  write_card(dir, code = "z <- pct(0.5)", front = "title: \"New question?\"")
  expect_equal(card_freshness(card, "test", dir = thumbs)$status, "fresh")
  write_card(dir, code = "z <- pct(0.25)")
  expect_equal(card_freshness(card, "test", dir = thumbs)$status, "stale_code")
})

test_that("card_freshness flags a changed R function and a missing thumbnail", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("ragg")
  dir <- withr::local_tempdir()
  thumbs <- file.path(dir, "card-thumbs")
  card <- write_card(dir, code = "z <- pct(0.5)")
  expect_equal(card_freshness(card, "test", dir = thumbs)$status, "missing")

  card_thumbnail(ggplot2::ggplot(), "test", card = card, dir = thumbs)
  side_path <- file.path(thumbs, "test.json")
  side <- jsonlite::read_json(side_path)
  side$functions$pct <- "an-older-hash"
  jsonlite::write_json(side, side_path, auto_unbox = TRUE)
  res <- card_freshness(card, "test", dir = thumbs)
  expect_equal(res$status, "stale_r")
  expect_equal(res$changed, "pct")
})

test_that("card_interactive wraps the same plot in a girafe widget", {
  skip_if_not_installed("ggiraph")
  w <- card_interactive(ggplot2::ggplot())
  expect_s3_class(w, "girafe")
})
