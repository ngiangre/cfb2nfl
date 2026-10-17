test_that("schema_hash is stable to row changes but sensitive to schema changes", {
  a <- tibble::tibble(x = 1:3, y = letters[1:3])
  b <- tibble::tibble(x = 1:10, y = letters[1:10])
  expect_equal(schema_hash(a), schema_hash(b))

  d <- tibble::tibble(x = 1:3, z = letters[1:3])
  expect_false(identical(schema_hash(a), schema_hash(d)))
})

test_that("audit_step records deltas and key coverage", {
  input <- tibble::tibble(id = c("1", "1", "2"), v = 1:3)
  output <- dplyr::distinct(input, id)
  rec <- audit_step(output, "dedup", "clean", input = input, keys = "id")
  expect_equal(rec$n_rows_in, 3L)
  expect_equal(rec$n_rows_out, 2L)
  expect_equal(rec$rows_delta, -1L)
  expect_equal(rec$n_keys_out, 2L)
  expect_true(is.na(rec$contract_passed))
})

test_that("audit_step measures join coverage and rows dropped", {
  input <- tibble::tibble(id = c("1", "2", "3"), v = 1:3)
  # left join that keeps only id 1 (dropping 2 and 3) and fans it out
  output <- tibble::tibble(id = c("1", "1"), v = c(1L, 1L), w = c("a", "b"))
  rec <- audit_step(output, "link", "link", input = input, keys = "id")
  expect_equal(rec$pct_keys_matched, 1 / 3)
  expect_equal(rec$keys_dropped, 2L)
  # fan-out shows as rows_delta, not as dropped keys
  expect_equal(rec$rows_delta, -1L)
})

test_that("audit_step coverage is NA without keys or input", {
  output <- tibble::tibble(id = 1:2, v = c(NA, 2))
  rec <- audit_step(output, "clean", "clean")
  expect_true(is.na(rec$pct_keys_matched))
  expect_true(is.na(rec$keys_dropped))
  # keys missing from the input leave coverage unknown, not zero
  rec2 <- audit_step(output, "clean", "clean", input = output["v"], keys = "id")
  expect_true(is.na(rec2$pct_keys_matched))
})

test_that("update_schema_history appends across runs without duplicating", {
  path <- file.path(withr::local_tempdir(), "history.csv")
  run1 <- tibble::tibble(
    step = c("a", "b"),
    n_cols_out = c(5L, 6L),
    schema_hash = c("h1", "h2"),
    timestamp = rep(as.POSIXct("2026-10-16 10:00:00", tz = "UTC"), 2),
    git_sha = rep("abc", 2)
  )
  h1 <- update_schema_history(run1, path)
  expect_equal(nrow(h1), 2L)

  # re-running the same rows appends nothing
  expect_equal(nrow(update_schema_history(run1, path)), 2L)

  # a later run appends and shows the drift when a hash changes
  run2 <- run1
  run2$schema_hash[1] <- "h1b"
  run2$timestamp <- as.POSIXct("2026-10-23 10:00:00", tz = "UTC")
  h2 <- update_schema_history(run2, path)
  expect_equal(nrow(h2), 4L)
  expect_equal(h2$schema_hash[h2$step == "a"], c("h1", "h1b"))
  # survives a fresh read from disk
  expect_equal(nrow(tibble::as_tibble(utils::read.csv(path))), 4L)
})

test_that("audit_step profiles NA per column", {
  output <- tibble::tibble(a = c(1, NA), b = c(NA, NA), c = c(1, 2))
  rec <- audit_step(output, "clean", "clean")
  expect_equal(rec$n_na_cells, 3L)
  expect_equal(rec$n_cols_with_na, 2L)
  prof <- rec$na_by_col[[1]]
  expect_equal(prof$col, c("b", "a"))
  expect_equal(prof$n_na, c(2L, 1L))
  expect_equal(prof$na_rate, c(1, 0.5))
  expect_equal(nrow(rec$na_by_col[[1]]), 2L)
})
