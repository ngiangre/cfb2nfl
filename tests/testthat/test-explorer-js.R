test_that("explorer JS modules pass their node tests", {
  node <- Sys.which("node")
  skip_if(!nzchar(node), "node is not installed")
  # vignettes/ is .Rbuildignored, so R CMD check skips; devtools::test() runs.
  dir <- testthat::test_path("..", "..", "vignettes", "explorer")
  skip_if_not(dir.exists(dir), "vignettes/explorer not present")
  files <- list.files(dir, "\\.test\\.mjs$", full.names = TRUE)
  expect_gt(length(files), 0L)
  out <- suppressWarnings(system2(
    node,
    c("--test", files),
    stdout = TRUE,
    stderr = TRUE
  ))
  status <- attr(out, "status")
  if (is.null(status)) {
    status <- 0L
  }
  expect_equal(status, 0L, info = paste(out, collapse = "\n"))
})
