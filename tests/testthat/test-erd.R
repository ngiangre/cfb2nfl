test_that("parse_erd_mermaid extracts nodes, edges, and name-guarded dashes", {
  lines <- c(
    "Some prose.",
    "```mermaid",
    "erDiagram",
    "  a }o--|| b : \"k1, k2\"",
    "  c |o..o| a : \"k (name-guarded)\"",
    "}",
    "```"
  )
  g <- parse_erd_mermaid(lines)
  expect_setequal(g$nodes$id, c("a", "b", "c"))
  expect_equal(nrow(g$edges), 2)
  expect_false(g$edges$dashes[g$edges$from == "a"])
  expect_true(g$edges$dashes[g$edges$from == "c"])
  expect_equal(g$edges$label[g$edges$to == "b"], "k1, k2")
})

test_that("dt_sql pushes search, sort, and paging into SQL", {
  s <- dt_sql(
    "\"picks\"",
    c("\"year\"", "\"round\"", "\"pick\""),
    search = "ward",
    col_search = c("", "2", ""),
    order_col = 2L,
    order_dir = "desc",
    start = 100L,
    length = 50L
  )
  expect_equal(s$total_sql, "SELECT COUNT(*) FROM \"picks\"")
  expect_match(
    s$filtered_sql,
    "CAST(\"year\" AS VARCHAR) ILIKE '%ward%'",
    fixed = TRUE
  )
  expect_match(
    s$filtered_sql,
    "CAST(\"round\" AS VARCHAR) ILIKE '%2%'",
    fixed = TRUE
  )
  expect_match(s$page_sql, "ORDER BY \"round\" DESC", fixed = TRUE)
  expect_match(s$page_sql, "LIMIT 50 OFFSET 100", fixed = TRUE)
  expect_no_match(s$page_sql, "WHERE WHERE")
})

test_that("dt_sql escapes single quotes and falls back on bad order index", {
  s <- dt_sql("\"t\"", c("\"a\"", "\"b\""), search = "o'brien", order_col = 99L)
  expect_match(s$filtered_sql, "o''brien", fixed = TRUE)
  expect_match(s$page_sql, "ORDER BY \"a\" ASC", fixed = TRUE)
})

test_that("app_dict parses every dictionary with grain and typed columns", {
  d <- app_dict()
  expect_gt(length(d), 15)
  expect_true(all(vapply(
    d,
    function(x) !is.null(x$grain) && !is.null(x$columns),
    logical(1)
  )))
  cols <- d[["picks"]]$columns
  expect_true(all(vapply(
    cols,
    function(c) !is.null(c$name) && !is.null(c$description),
    logical(1)
  )))
  expect_true(all(c("player_stats", "nfl_player_stats", "teams") %in% names(d)))
})
