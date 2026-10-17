# cfbd_get retries transient CFBD failures (decision 0028): the weekly CI
# refresh makes ~60 back-to-back calls and CFBD sheds load with 503s, so a
# single blip must not fail the whole refresh. NOTE: httr2's retry loop runs
# in the real curl transport and is NOT engaged for mocked responses, so the
# retry behavior is asserted via the request's policy; the transient predicate
# itself is unit-tested against representative statuses.

test_that("cfbd_request carries the retry policy, auth header and query", {
  skip_if_not_installed("httr2")
  Sys.setenv(CFBD_API_KEY = "test-key")
  withr::defer(Sys.unsetenv("CFBD_API_KEY"))

  req <- cfbd_request("/draft/picks", list(year = 2015))
  expect_equal(req$policies$retry_max_tries, 5)
  expect_equal(req$policies$retry_max_wait, 120)
  expect_type(req$policies$retry_is_transient, "closure")
  # The policy flags the transient statuses CFBD sheds load with.
  is_transient <- req$policies$retry_is_transient
  expect_true(is_transient(httr2::response(503)))
  expect_true(is_transient(httr2::response(429)))
  expect_true(is_transient(httr2::response(500)))
  expect_false(is_transient(httr2::response(404)))
  expect_false(is_transient(httr2::response(200)))

  # Authorization is set (httr2 redacts its VALUE in dry runs by design).
  expect_false(is.null(req$headers$Authorization))
  expect_match(req$url, "collegefootballdata.com/draft/picks")
  expect_match(req$url, "year=2015")
})

test_that("cfbd_request sends the bearer token at perform time", {
  skip_if_not_installed("httpuv") # req_dry_run needs it; absent in R CMD check
  skip_if_not_installed("httr2")
  Sys.setenv(CFBD_API_KEY = "test-key")
  withr::defer(Sys.unsetenv("CFBD_API_KEY"))

  dry <- httr2::req_dry_run(cfbd_request("/roster"), quiet = TRUE)
  expect_false(is.null(dry$headers$authorization))
})

test_that("cfbd_get parses a successful response body", {
  skip_if_not_installed("httr2")
  Sys.setenv(CFBD_API_KEY = "test-key")
  withr::defer(Sys.unsetenv("CFBD_API_KEY"))

  out <- httr2::with_mocked_responses(
    \(req) {
      httr2::response_json(status = 200L, body = list(list(a = 1), list(a = 2)))
    },
    cfbd_get("/roster")
  )
  expect_equal(nrow(out), 2L)
  expect_equal(out$a, c(1, 2))
})

test_that("cfbd_request errors without an API key", {
  Sys.unsetenv("CFBD_API_KEY")
  withr::defer(Sys.setenv(CFBD_API_KEY = "test-key"))
  expect_error(cfbd_request("/roster"), "CFBD_API_KEY")
})
