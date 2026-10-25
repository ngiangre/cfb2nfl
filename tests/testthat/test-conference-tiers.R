test_that("build_conference_tiers assigns season-aware tiers", {
  ps <- data.frame(
    season = c(2015L, 2015L, 2023L, 2024L, 2012L, 2013L, 2015L),
    conference = c(
      "SEC", # Power
      "Sun Belt", # G5
      "Pac-12", # Power pre-2024
      "Pac-12", # -> G5 from 2024
      "Western Athletic", # G5 through 2012
      "Western Athletic", # -> FCS from 2013
      "Ivy" # unknown -> tier 1
    )
  )
  out <- build_conference_tiers(ps)

  tier_of <- function(conf, yr) {
    out$tier[out$conference == conf & out$season == yr]
  }
  expect_equal(tier_of("SEC", 2015), 3L)
  expect_equal(tier_of("Sun Belt", 2015), 2L)
  expect_equal(tier_of("Pac-12", 2023), 3L)
  expect_equal(tier_of("Pac-12", 2024), 2L)
  expect_equal(tier_of("Western Athletic", 2012), 2L)
  expect_equal(tier_of("Western Athletic", 2013), 1L)
  expect_equal(tier_of("Ivy", 2015), 1L)

  # tier_label matches the tier level mapping and there are no gaps.
  expect_setequal(unique(out$tier_label), names(conference_tier_levels()))
  expect_false(anyNA(out$tier_label))
})

test_that("parquet_asset tracks an existing file when refresh is off", {
  Sys.setenv(CFB2NFL_REFRESH = "false")
  on.exit(Sys.unsetenv("CFB2NFL_REFRESH"), add = TRUE)
  path <- tempfile(fileext = ".parquet")
  on.exit(unlink(path), add = TRUE)
  file.create(path)

  # Off + file present: returns path without evaluating build().
  expect_equal(
    parquet_asset(path, function() stop("should not ingest")),
    path
  )
})

test_that("parquet_asset errors when off and the asset is missing", {
  Sys.setenv(CFB2NFL_REFRESH = "false")
  on.exit(Sys.unsetenv("CFB2NFL_REFRESH"), add = TRUE)
  expect_error(
    parquet_asset(tempfile(fileext = ".parquet"), function() NULL),
    "not found"
  )
})

test_that("parquet_asset ingests and writes in refresh mode", {
  skip_if_not_installed("arrow")
  Sys.setenv(CFB2NFL_REFRESH = "true")
  on.exit(Sys.unsetenv("CFB2NFL_REFRESH"), add = TRUE)
  path <- tempfile(fileext = ".parquet")
  on.exit(unlink(path), add = TRUE)

  built <- FALSE
  out <- parquet_asset(path, function() {
    built <<- TRUE
    data.frame(x = 1:3)
  })

  expect_true(built)
  expect_equal(out, path)
  expect_equal(nrow(arrow::read_parquet(path)), 3L)
})
