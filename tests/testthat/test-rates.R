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
