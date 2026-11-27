test_that("fmt adds thousands separators and rounds to the digits asked", {
  expect_equal(fmt(1234567), "1,234,567")
  expect_equal(fmt(1234.567, 1), "1,234.6")
  expect_equal(fmt(c(5, 12000)), c("5", "12,000"))
})

test_that("fmt accepts integers and numeric strings", {
  expect_equal(fmt(42L), "42")
  expect_equal(fmt("2500"), "2,500")
})

test_that("pct turns a share into a percent string", {
  expect_equal(pct(0.1234), "12.3%")
  expect_equal(pct(0.1234, 0), "12%")
  expect_equal(pct(c(0, 1)), c("0.0%", "100.0%"))
})

test_that("wilson matches the closed-form interval and stays in [0, 1]", {
  ci <- wilson(30, 100)
  expect_named(ci, c("lo", "hi"))
  expect_equal(unname(ci), c(0.2189, 0.3958), tolerance = 1e-3)
  expect_equal(unname(wilson(0, 10)["lo"]), 0)
  expect_equal(unname(wilson(10, 10)["hi"]), 1)
})

test_that("wilson matches prop.test without continuity correction", {
  ref <- stats::prop.test(17, 40, correct = FALSE)$conf.int
  z <- stats::qnorm(0.975)
  expect_equal(unname(wilson(17, 40, z)), as.numeric(ref), tolerance = 1e-8)
})

test_that("and_join reads a vector as an English list", {
  expect_equal(
    and_join(c("Burrow", "Ward", "Travis")),
    "Burrow, Ward and Travis"
  )
  expect_equal(and_join(c("Burrow", "Ward")), "Burrow and Ward")
  expect_equal(and_join("Burrow"), "Burrow")
})
